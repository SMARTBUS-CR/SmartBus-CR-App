import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/services/session_check.dart';
import '../models/gps_fix.dart';
import 'gps_location_service.dart';

/// High-level state of the trip GPS transmission.
enum TripTrackingState {
  idle,
  starting,
  tracking,
  stopped,

  /// The OS location services (GPS) are turned off on the device.
  locationServicesDisabled,

  /// The user denied the location permission.
  permissionDenied,

  /// The backend refused the readings for good (not the assigned driver, the
  /// trip is not in progress, the trip does not exist or the session expired).
  /// Transmission stopped; [TripTrackingSnapshot.lastError] says why.
  rejected,
}

/// Immutable snapshot the UI watches (via [TripLocationSender.snapshot]).
@immutable
class TripTrackingSnapshot {
  const TripTrackingSnapshot({
    this.state = TripTrackingState.idle,
    this.tripId,
    this.lastFixAt,
    this.lastSentAt,
    this.sentCount = 0,
    this.pendingCount = 0,
    this.lastError,
    this.sessionExpired = false,
    this.latitude,
    this.longitude,
  });

  /// Position of the last GPS reading (the bus), to draw it on the map.
  final double? latitude;
  final double? longitude;

  final TripTrackingState state;

  /// UUID of the trip being tracked.
  final String? tripId;

  /// When the last GPS reading was obtained from the device.
  final DateTime? lastFixAt;

  /// When the last reading was successfully stored by the backend.
  final DateTime? lastSentAt;

  /// Readings confirmed by the backend since [TripLocationSender.start].
  final int sentCount;

  /// Readings waiting in the retry queue (grows when offline).
  final int pendingCount;

  /// User-friendly message of the last failure, or `null` when healthy.
  final String? lastError;

  /// [TripTrackingState.rejected] because the backend answered 401: the
  /// session is no longer valid, so the UI must send the driver to Login
  /// (retrying would get 401 again).
  final bool sessionExpired;

  bool get isTracking => state == TripTrackingState.tracking;

  TripTrackingSnapshot copyWith({
    TripTrackingState? state,
    String? tripId,
    DateTime? lastFixAt,
    DateTime? lastSentAt,
    int? sentCount,
    int? pendingCount,
    String? lastError,
    bool clearError = false,
    bool? sessionExpired,
    double? latitude,
    double? longitude,
  }) {
    return TripTrackingSnapshot(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      state: state ?? this.state,
      tripId: tripId ?? this.tripId,
      lastFixAt: lastFixAt ?? this.lastFixAt,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      sentCount: sentCount ?? this.sentCount,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
      sessionExpired: sessionExpired ?? this.sessionExpired,
    );
  }
}

/// Sends the driver's GPS location to the backend **periodically** during a trip
/// (issue-4). No UI: [snapshot] is what the screen renders.
///
/// ```dart
/// final sender = TripLocationSender();
/// await sender.start(tripId: tripUuid);   // asks permission, then sends every [interval]
/// // ValueListenableBuilder(valueListenable: sender.snapshot, ...)
/// await sender.stop();
/// sender.dispose();
/// ```
///
/// **Background:** while tracking, a location *stream* runs with a foreground
/// notification on Android (`ForegroundNotificationConfig`) and background
/// location updates on iOS. This keeps the app sending with the screen locked
/// or another app on top. It is best-effort: if Android still decides to destroy
/// the activity (low memory), tracking stops until the driver reopens the app —
///
/// **Newest first, no backlog:** the passenger's map needs where the bus is
/// NOW, and the GPS service ignores a reading older than the current position
/// (and only stores the start and the end of the trip). So at most one
/// reading is in flight and **one** waits: a newer reading replaces the
/// waiting one. A slow request never builds a queue of old positions that
/// would show the bus behind. [TripTrackingSnapshot.pendingCount] is 0 or 1.
///
/// **Retry:** a failed send (network / 5xx / 429 only) is retried on the next
/// tick, unless a newer reading has arrived meanwhile (then that one is sent).
///
/// **End of the trip:** [sendFinal] sends the current position marked
/// `final`, which the GPS service stores as the trip's end.
///
/// **Rejected:** 401 (session expired), 403 (not the driver assigned to the
/// trip), 404 (the trip does not exist) and 409 (the trip is not in progress)
/// will fail for every next fix too, so transmission stops with
/// [TripTrackingState.rejected] instead of failing every few seconds. Any other
/// 4xx (bad data) only drops that fix.
///
/// A `202` (`broadcast_only`, `duplicate`, `stale`) is a success: the backend
/// accepted the reading, even if it did not store it.
class TripLocationSender {
  TripLocationSender({
    GpsLocationService? service,
    this.interval = const Duration(seconds: 5),
    this.accuracy = LocationAccuracy.high,
    SessionExpiryCheck? sessionCheck,
  }) : _service = service ?? GpsLocationService(),
       _confirmSessionExpired = sessionCheck ?? confirmSessionExpired;

  final GpsLocationService _service;

  /// Asked before treating a `401` as "session expired" (tests fake it).
  final SessionExpiryCheck _confirmSessionExpired;

  /// How often a reading is sent.
  final Duration interval;

  final LocationAccuracy accuracy;

  /// The current state — watch this from the UI.
  final ValueNotifier<TripTrackingSnapshot> snapshot = ValueNotifier(
    const TripTrackingSnapshot(),
  );

  /// The newest reading not sent yet (replaced by every newer one).
  GpsFix? _waiting;
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Position? _latest;
  String _tripId = '';
  bool _flushing = false;
  bool _disposed = false;

  /// Starts periodic transmission for [tripId] (UUID of the trip).
  ///
  /// Requests the location permission if needed. If the user denies it, or the
  /// device's location services are off, [snapshot] reflects it and nothing is
  /// sent.
  Future<void> start({required String tripId}) async {
    if (snapshot.value.isTracking || _disposed) return;
    _tripId = tripId;
    _lastStamp = null;
    // Fresh counters: the sender lives for the whole session and may have
    // sent another trip before (see ActiveTripTracking).
    snapshot.value = TripTrackingSnapshot(
      state: TripTrackingState.starting,
      tripId: tripId,
    );

    final blocker = await _ensureLocationAccess();
    if (blocker != null) {
      _set(state: blocker);
      return;
    }

    // The stream keeps a foreground notification (Android) / background updates
    // (iOS) alive. Each new position is sent **as soon as it arrives** (not on
    // the next tick: that added up to [interval] of delay for the passenger).
    // The timer only covers a stopped bus, which gets no new positions.
    _positionSub =
        Geolocator.getPositionStream(locationSettings: _buildLocationSettings())
            .listen(
              _onPosition,
              onError: (Object _) => _set(
                lastError: 'No se pudo obtener la ubicación del dispositivo.',
              ),
            );

    _timer = Timer.periodic(interval, (_) => _tick());
    _set(state: TripTrackingState.tracking);
    unawaited(_tick()); // first reading now, don't wait a full interval
  }

  /// A new position from the OS: sent right away.
  void _onPosition(Position position) {
    if (_disposed || !snapshot.value.isTracking) return;
    _latest = position;
    _queue(position);
    _sentSinceTick = true;
    unawaited(_flush());
  }

  /// A reading was queued since the last tick (the bus is moving).
  bool _sentSinceTick = false;

  /// Sends the bus's current position as the **end of the trip** (`final`:
  /// the GPS service stores it). Call it right before completing the trip,
  /// while it is still in progress. Best effort: a failure is ignored (the
  /// trip is completed anyway).
  Future<void> sendFinal() async {
    final snap = snapshot.value;
    final latitude = snap.latitude;
    final longitude = snap.longitude;
    if (!snap.isTracking || latitude == null || longitude == null) return;
    // Stamped after any reading already sent, so it is never ignored as a
    // duplicate or a late one.
    final last = _lastStamp;
    var now = DateTime.now().toUtc();
    if (last != null && !now.isAfter(last)) {
      now = last.add(const Duration(milliseconds: 1));
    }
    _lastStamp = now;
    final fix = GpsFix(
      tripId: _tripId,
      latitude: latitude,
      longitude: longitude,
      recordedAt: now,
      isFinal: true,
    );
    try {
      await _service.send(fix);
      _set(lastSentAt: DateTime.now(), sentCount: snapshot.value.sentCount + 1);
    } on ApiException catch (_) {
      // The end position is a nice-to-have; finishing must not wait on it.
    }
  }

  /// Stops transmission. The waiting (un-sent) reading is discarded and the
  /// foreground notification disappears.
  void stop() {
    _shutdown();
    _set(state: TripTrackingState.stopped, pendingCount: 0);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _positionSub?.cancel();
    snapshot.dispose();
  }

  // --- internals --------------------------------------------------------

  /// Cancels the timer and the location stream and drops the waiting reading.
  void _shutdown() {
    _timer?.cancel();
    _timer = null;
    final sub = _positionSub;
    _positionSub = null;
    if (sub != null) unawaited(sub.cancel());
    _latest = null;
    _waiting = null;
    _sentSinceTick = false;
  }

  /// Message for the driver when the backend refuses the readings for good, or
  /// `null` when the error only affects this fix (or can be retried).
  static String? _rejectionMessage(ApiException e) {
    switch (e.type) {
      case ApiErrorType.unauthorized:
        return e.message; // "Tu sesión expiró. Inicia sesión nuevamente."
      case ApiErrorType.forbidden:
        return 'No eres el conductor asignado a este viaje.';
      case ApiErrorType.notFound:
        return 'No se encontró el viaje.';
      case ApiErrorType.conflict:
        return 'El viaje no está en curso: todavía no se ha iniciado o ya '
            'terminó.';
      default:
        return null;
    }
  }

  /// Minimum displacement (meters) before the OS emits a new position on the
  /// stream. This is a **battery/GPS-radio** optimization only — it does NOT
  /// reduce how often a fix is *sent*: [_tick] still runs every [interval] and
  /// sends whatever is in [_latest], even if it hasn't changed. Deciding which
  /// fixes are worth *persisting* (distance/time threshold, dedup while
  /// stopped, …).
  static const int _distanceFilterMeters = 10;

  LocationSettings _buildLocationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: _distanceFilterMeters,
          intervalDuration: interval,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'SmartBus · recorrido activo',
            notificationText:
                'Enviando la ubicación del autobús. No cierres la app.',
            notificationChannelName: 'Recorrido en curso',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: _distanceFilterMeters,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return LocationSettings(accuracy: accuracy);
    }
  }

  /// Every [interval]: when no new position arrived since the last tick (a
  /// stopped bus, or the first reading), sends the latest one again
  /// (re-stamped "now", see [_stamped]); otherwise just retries a failed send.
  Future<void> _tick() async {
    if (_disposed) return;
    if (_sentSinceTick) {
      _sentSinceTick = false;
      await _flush();
      return;
    }

    final position = _latest ?? await _firstPosition();
    if (_disposed || !snapshot.value.isTracking) return;
    // A real position may have arrived while asking for the first one.
    if (position != null && !_sentSinceTick) _queue(position);
    _sentSinceTick = false;
    await _flush();
  }

  /// The trip's first reading is stored as its **start**, so it must be where
  /// the bus is now: the OS's last known position only if it is recent,
  /// otherwise a fresh fix (at most [_firstFixTimeout]).
  Future<Position?> _firstPosition() async {
    try {
      final known = await Geolocator.getLastKnownPosition();
      if (known != null &&
          DateTime.now().difference(known.timestamp).abs() <=
              _maxLastKnownAge) {
        return known;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: _firstFixTimeout,
        ),
      );
    } catch (_) {
      // No fix yet (timeout, GPS off, plugin error): the stream or the next
      // tick will bring one.
      return null;
    }
  }

  /// A last known position older than this is not the bus's current one.
  static const _maxLastKnownAge = Duration(seconds: 30);
  static const _firstFixTimeout = Duration(seconds: 10);

  /// [position] becomes the reading to send next; the map shows it.
  void _queue(Position position) {
    _enqueue(_stamped(GpsFix.fromPosition(position, tripId: _tripId)));
    _set(
      lastFixAt: DateTime.now(),
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// Time of the last reading queued, so each new one is strictly later.
  DateTime? _lastStamp;

  /// A stopped bus gets no new position from the OS (distance filter), so the
  /// same reading comes back every tick: it is re-stamped "now" (the bus is
  /// still there now). Otherwise the GPS service would ignore it as a
  /// duplicate and the passenger would see "Señal débil" at every stop.
  GpsFix _stamped(GpsFix fix) {
    final last = _lastStamp;
    var stamped = fix;
    if (last != null && !fix.recordedAt.isAfter(last)) {
      var now = DateTime.now().toUtc();
      if (!now.isAfter(last)) now = last.add(const Duration(milliseconds: 1));
      stamped = GpsFix(
        tripId: fix.tripId,
        latitude: fix.latitude,
        longitude: fix.longitude,
        speedKmh: fix.speedKmh,
        accuracyMeters: fix.accuracyMeters,
        recordedAt: now,
      );
    }
    _lastStamp = stamped.recordedAt;
    return stamped;
  }

  /// [fix] becomes the reading to send next, replacing an older waiting one.
  void _enqueue(GpsFix fix) {
    _waiting = fix;
    _set(pendingCount: 1);
  }

  int get _pendingCount => _waiting == null ? 0 : 1;

  /// Sends the waiting reading; when it is done, the newest one that arrived
  /// meanwhile (if any) right away. Only one request at a time.
  Future<void> _flush() async {
    if (_flushing || _waiting == null) return;
    _flushing = true;
    try {
      while (!_disposed) {
        final fix = _waiting;
        if (fix == null) break;
        _waiting = null;
        try {
          await _service.send(fix);
          _set(
            lastSentAt: DateTime.now(),
            sentCount: snapshot.value.sentCount + 1,
            pendingCount: _pendingCount,
            clearError: true,
          );
        } on ApiException catch (e) {
          if (_isRetryable(e)) {
            // Try again on the next tick, unless a newer reading came in.
            _waiting ??= fix;
            _set(lastError: e.message, pendingCount: _pendingCount);
            break;
          }
          if (e.type == ApiErrorType.unauthorized &&
              !await _sessionReallyExpired()) {
            // The GPS service could not check the token with the Gateway
            // (slow / down) but the token works: keep it and try again.
            _waiting ??= fix;
            _set(
              lastError: 'Verificando la sesión…',
              pendingCount: _pendingCount,
            );
            break;
          }
          final rejection = _rejectionMessage(e);
          if (rejection != null) {
            // Every next fix would fail the same way: stop sending.
            _shutdown();
            _set(
              state: TripTrackingState.rejected,
              lastError: rejection,
              pendingCount: 0,
              sessionExpired: e.type == ApiErrorType.unauthorized,
            );
            break;
          }
          // Other 4xx: retrying will not help. Drop this fix and go on.
          _set(lastError: e.message, pendingCount: _pendingCount);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// When the Authentication Service last said the token works.
  DateTime? _sessionConfirmedAt;

  /// A `401` from the GPS service only stops sending when the Authentication
  /// Service confirms it ([confirmSessionExpired]). While it said "valid" in
  /// the last [_sessionRecheckAfter], it is not asked again.
  Future<bool> _sessionReallyExpired() async {
    final confirmed = _sessionConfirmedAt;
    if (confirmed != null &&
        DateTime.now().difference(confirmed) < _sessionRecheckAfter) {
      return false;
    }
    final expired = await _confirmSessionExpired();
    if (!expired) _sessionConfirmedAt = DateTime.now();
    return expired;
  }

  static const _sessionRecheckAfter = Duration(seconds: 60);

  bool _isRetryable(ApiException e) {
    switch (e.type) {
      case ApiErrorType.noConnection:
      case ApiErrorType.timeout:
      case ApiErrorType.serverError:
      case ApiErrorType.serviceUnavailable:
      case ApiErrorType.tooManyRequests:
        return true;
      default:
        return false;
    }
  }

  Future<TripTrackingState?> _ensureLocationAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TripTrackingState.locationServicesDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return TripTrackingState.permissionDenied;
    }
    return null;
  }

  void _set({
    TripTrackingState? state,
    String? tripId,
    DateTime? lastFixAt,
    DateTime? lastSentAt,
    int? sentCount,
    int? pendingCount,
    String? lastError,
    bool clearError = false,
    bool? sessionExpired,
    double? latitude,
    double? longitude,
  }) {
    if (_disposed) return;
    snapshot.value = snapshot.value.copyWith(
      latitude: latitude,
      longitude: longitude,
      state: state,
      tripId: tripId,
      lastFixAt: lastFixAt,
      lastSentAt: lastSentAt,
      sentCount: sentCount,
      pendingCount: pendingCount,
      lastError: lastError,
      clearError: clearError,
      sessionExpired: sessionExpired,
    );
  }
}
