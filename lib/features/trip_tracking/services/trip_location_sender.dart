import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_exception.dart';
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
  });

  final TripTrackingState state;
  final int? tripId;

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

  bool get isTracking => state == TripTrackingState.tracking;

  TripTrackingSnapshot copyWith({
    TripTrackingState? state,
    int? tripId,
    DateTime? lastFixAt,
    DateTime? lastSentAt,
    int? sentCount,
    int? pendingCount,
    String? lastError,
    bool clearError = false,
  }) {
    return TripTrackingSnapshot(
      state: state ?? this.state,
      tripId: tripId ?? this.tripId,
      lastFixAt: lastFixAt ?? this.lastFixAt,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      sentCount: sentCount ?? this.sentCount,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Sends the driver's GPS location to the backend **periodically** during a trip
/// (issue-4). No UI: [snapshot] is what the screen renders.
///
/// ```dart
/// final sender = TripLocationSender();
/// await sender.start(tripId: 25);   // asks permission, then sends every [interval]
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
/// a dedicated background service package would be needed to fully guarantee it.
///
/// **Retry:** a failed send stays in an in-memory queue and is retried on the
/// next tick — but only for network / 5xx / 429 errors. A 4xx (bad data, expired
/// token) is not retried: the fix is dropped and the reason surfaces in
/// [TripTrackingSnapshot.lastError]. The queue is capped at [maxQueue] so a long
/// outage cannot grow memory without bound (oldest fixes are dropped first).
class TripLocationSender {
  TripLocationSender({
    GpsLocationService? service,
    this.interval = const Duration(seconds: 5),
    this.maxQueue = 120,
    this.accuracy = LocationAccuracy.high,
  }) : _service = service ?? GpsLocationService();

  final GpsLocationService _service;

  /// How often a reading is sent.
  final Duration interval;

  /// Max number of un-sent fixes kept in memory during an outage.
  final int maxQueue;

  final LocationAccuracy accuracy;

  /// The current state — watch this from the UI.
  final ValueNotifier<TripTrackingSnapshot> snapshot =
      ValueNotifier(const TripTrackingSnapshot());

  final Queue<GpsFix> _pending = Queue<GpsFix>();
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Position? _latest;
  int _tripId = 0;
  bool _flushing = false;
  bool _disposed = false;

  /// Starts periodic transmission for [tripId].
  ///
  /// Requests the location permission if needed. If the user denies it, or the
  /// device's location services are off, [snapshot] reflects it and nothing is
  /// sent.
  Future<void> start({required int tripId}) async {
    if (snapshot.value.isTracking || _disposed) return;
    _tripId = tripId;
    _set(state: TripTrackingState.starting, tripId: tripId, clearError: true);

    final blocker = await _ensureLocationAccess();
    if (blocker != null) {
      _set(state: blocker);
      return;
    }

    // The stream keeps a foreground notification (Android) / background updates
    // (iOS) alive and feeds [_latest]; the timer paces the sends.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      (position) => _latest = position,
      onError: (Object _) =>
          _set(lastError: 'No se pudo obtener la ubicación del dispositivo.'),
    );

    _timer = Timer.periodic(interval, (_) => _tick());
    _set(state: TripTrackingState.tracking);
    unawaited(_tick()); // first reading now, don't wait a full interval
  }

  /// Stops transmission. Queued (un-sent) fixes are discarded and the
  /// foreground notification disappears.
  void stop() {
    _timer?.cancel();
    _timer = null;
    final sub = _positionSub;
    _positionSub = null;
    if (sub != null) unawaited(sub.cancel());
    _latest = null;
    _pending.clear();
    _set(state: TripTrackingState.stopped, pendingCount: 0);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _positionSub?.cancel();
    snapshot.dispose();
  }

  // --- internals --------------------------------------------------------

  LocationSettings _buildLocationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          intervalDuration: interval,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'SmartBus · recorrido activo',
            notificationText: 'Enviando la ubicación del autobús',
            notificationChannelName: 'Recorrido en curso',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return LocationSettings(accuracy: accuracy);
    }
  }

  Future<void> _tick() async {
    if (_disposed) return;

    final position = _latest ?? await Geolocator.getLastKnownPosition();
    if (position != null) {
      _enqueue(GpsFix.fromPosition(position, tripId: _tripId));
      _set(lastFixAt: DateTime.now());
    }
    await _flush();
  }

  void _enqueue(GpsFix fix) {
    _pending.addLast(fix);
    while (_pending.length > maxQueue) {
      _pending.removeFirst();
    }
    _set(pendingCount: _pending.length);
  }

  Future<void> _flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty && !_disposed) {
        final fix = _pending.first;
        try {
          await _service.send(fix);
          _pending.removeFirst();
          _set(
            lastSentAt: DateTime.now(),
            sentCount: snapshot.value.sentCount + 1,
            pendingCount: _pending.length,
            clearError: true,
          );
        } on ApiException catch (e) {
          if (_isRetryable(e)) {
            // Keep the queue and try again on the next tick.
            _set(lastError: e.message, pendingCount: _pending.length);
            break;
          }
          // 4xx: retrying will not help. Drop this fix and continue.
          _pending.removeFirst();
          _set(lastError: e.message, pendingCount: _pending.length);
        }
      }
    } finally {
      _flushing = false;
    }
  }

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
    int? tripId,
    DateTime? lastFixAt,
    DateTime? lastSentAt,
    int? sentCount,
    int? pendingCount,
    String? lastError,
    bool clearError = false,
  }) {
    if (_disposed) return;
    snapshot.value = snapshot.value.copyWith(
      state: state,
      tripId: tripId,
      lastFixAt: lastFixAt,
      lastSentAt: lastSentAt,
      sentCount: sentCount,
      pendingCount: pendingCount,
      lastError: lastError,
      clearError: clearError,
    );
  }
}
