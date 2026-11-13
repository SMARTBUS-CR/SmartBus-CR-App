import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../models/trip_tracking.dart';
import 'gps_location_service.dart';
import 'trip_live_feed.dart';

/// Builds the tracker of a trip (tests plug in fakes).
typedef LiveTripTrackerFactory = LiveTripTracker Function(String tripId);

enum LiveTripPhase {
  /// Asking the backend for the trip for the first time.
  loading,

  /// Following the trip (scheduled or in progress).
  tracking,

  /// The trip completed or was cancelled: nothing else to follow.
  finished,

  /// The trip does not exist.
  notFound,

  /// The first request failed (no connection, server down, …). See [LiveTripState.error].
  failed,
}

/// What the passenger's map shows. Immutable; see [LiveTripTracker.state].
@immutable
class LiveTripState {
  const LiveTripState({
    this.phase = LiveTripPhase.loading,
    this.status,
    this.position,
    this.positionSeenAt,
    this.realtime = false,
    this.error,
  });

  final LiveTripPhase phase;
  final TripStatus? status;

  /// Latest bus position (the one with the greatest `recorded_at`).
  final BusPosition? position;

  /// When [position] was taken, **on this phone's clock** (the driver's phone
  /// clock may be off, so its `recorded_at` is only used to order readings).
  final DateTime? positionSeenAt;

  /// The real-time connection is up (positions arrive by themselves).
  final bool realtime;

  /// Message of the last failed request, or `null`.
  final String? error;

  /// Freshness of [position] at [now] (same thresholds as the GPS service).
  TrackingFreshness freshnessAt(DateTime now) {
    if (status != TripStatus.inProgress) return TrackingFreshness.notTracking;
    final seenAt = positionSeenAt;
    if (position == null || seenAt == null) return TrackingFreshness.noSignal;
    return TrackingFreshness.forAge(now.difference(seenAt));
  }

  LiveTripState copyWith({
    LiveTripPhase? phase,
    TripStatus? status,
    BusPosition? position,
    DateTime? positionSeenAt,
    bool? realtime,
    String? error,
    bool clearError = false,
  }) => LiveTripState(
    phase: phase ?? this.phase,
    status: status ?? this.status,
    position: position ?? this.position,
    positionSeenAt: positionSeenAt ?? this.positionSeenAt,
    realtime: realtime ?? this.realtime,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Follows the bus of one trip for the passenger's map (HU3).
///
/// 1. `GET /gps/trips/{id}/location` → status + current position.
/// 2. Subscribes to `private-trip.{id}`: each `BusLocationUpdated` moves the
///    bus (only if it is newer than the one shown: events can arrive out of
///    order on mobile networks).
/// 3. Asks the position again while it is not live: no real-time
///    subscription (the socket is closed, or the trip's channel is not
///    confirmed yet), or the updates stopped. The driver sends every ~5 s, so
///    it asks at that same pace ([pollInterval]) — the bus keeps moving on the
///    map even when the WebSocket does not deliver — and [silenceThreshold]
///    (7 s, a missed reading) without a position is enough to ask: that is
///    also how "trip finished" is detected (`status = completed`) in
///    ~7–10 s, without any event from the Dashboard. The conditions are
///    checked every second ([checkEvery]), so a request is never late by a
///    whole extra interval. A trip that has not started is asked less often
///    ([idlePollInterval]).
/// 4. Asks again when the connection comes back (events sent while it was
///    down are lost) and when the channel is refused.
class LiveTripTracker {
  LiveTripTracker({
    required this.tripId,
    GpsLocationService? service,
    this.feed,
    this.pollInterval = const Duration(seconds: 5),
    this.idlePollInterval = const Duration(seconds: 15),
    this.silenceThreshold = const Duration(seconds: 7),
    this.checkEvery = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _service = service ?? GpsLocationService(),
       _clock = clock ?? DateTime.now;

  /// Tracker with the app config: GPS service through the Gateway, plus the
  /// real-time feed when `REVERB_APP_KEY` is set (otherwise it polls).
  factory LiveTripTracker.withDefaults(String tripId) {
    final service = GpsLocationService();
    return LiveTripTracker(
      tripId: tripId,
      service: service,
      feed: ReverbTripFeed.fromConfig(service: service),
    );
  }

  final String tripId;

  /// Real-time positions; `null` = only polling.
  final TripLiveFeed? feed;

  /// Minimum time between two requests while the trip is in progress (the
  /// driver's sending pace).
  final Duration pollInterval;

  /// Minimum time between two requests while the trip has not started.
  final Duration idlePollInterval;

  /// Time without a new position after which the bus is "silent" and the
  /// backend is asked (did the trip finish?).
  final Duration silenceThreshold;

  /// How often the conditions above are checked (no request by itself).
  final Duration checkEvery;

  final GpsLocationService _service;
  final DateTime Function() _clock;

  final ValueNotifier<LiveTripState> state = ValueNotifier(
    const LiveTripState(),
  );

  StreamSubscription<BusLocationUpdate>? _locationSub;
  StreamSubscription<Object>? _rejectionSub;
  Timer? _pollTimer;
  DateTime? _lastRequestAt;
  bool _following = false;
  bool _wasConnected = false;
  bool _refreshing = false;
  bool _feedClosed = false;
  bool _disposed = false;

  /// Loads the trip and starts following it.
  Future<void> start() async {
    if (_disposed) return;
    _set(state.value.copyWith(phase: LiveTripPhase.loading, clearError: true));
    _lastRequestAt = _clock();
    try {
      final tracking = await _service.latestForTrip(tripId);
      if (_disposed) return;
      _apply(tracking);
      if (!tracking.status.isFinished) _follow();
    } on ApiException catch (e) {
      _set(
        state.value.copyWith(
          phase: e.type == ApiErrorType.notFound
              ? LiveTripPhase.notFound
              : LiveTripPhase.failed,
          error: e.message,
        ),
      );
    } catch (_) {
      _set(
        state.value.copyWith(
          phase: LiveTripPhase.failed,
          error: 'No se pudo obtener la ubicación del bus.',
        ),
      );
    }
  }

  /// Asks the backend for the current status and position.
  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    _lastRequestAt = _clock();
    try {
      final tracking = await _service.latestForTrip(tripId);
      if (_disposed) return;
      _apply(tracking);
    } on ApiException catch (e) {
      if (e.type == ApiErrorType.notFound) {
        _stopFollowing();
        _set(
          state.value.copyWith(phase: LiveTripPhase.notFound, error: e.message),
        );
      } else {
        // Keep showing the last position; it only gets older.
        _set(state.value.copyWith(error: e.message));
      }
    } catch (_) {
      _set(state.value.copyWith(error: 'No se pudo actualizar la ubicación.'));
    } finally {
      _refreshing = false;
    }
  }

  void dispose() {
    _stopFollowing();
    _disposed = true;
    state.dispose();
  }

  // --- internals --------------------------------------------------------

  void _follow() {
    if (_following) return;
    _following = true;
    final feed = this.feed;
    if (feed != null) {
      _locationSub = feed.locations.listen(_onLive);
      _rejectionSub = feed.rejections.listen((_) => unawaited(refresh()));
      feed.connected.addListener(_onConnection);
      _wasConnected = feed.connected.value;
      _set(state.value.copyWith(realtime: _wasConnected));
      feed.follow(tripId);
    }
    _pollTimer = Timer.periodic(checkEvery, (_) => _check());
  }

  /// Asks the backend when the positions are not arriving by themselves, at
  /// most once every [pollInterval] ([idlePollInterval] before the trip
  /// starts).
  void _check() {
    if (!_needsPolling) return;
    final interval = state.value.status == TripStatus.inProgress
        ? pollInterval
        : idlePollInterval;
    final last = _lastRequestAt;
    if (last != null && _clock().difference(last) < interval) return;
    unawaited(refresh());
  }

  void _stopFollowing() {
    _following = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _locationSub?.cancel();
    _locationSub = null;
    _rejectionSub?.cancel();
    _rejectionSub = null;
    final feed = this.feed;
    if (feed != null && !_feedClosed) {
      _feedClosed = true;
      feed.connected.removeListener(_onConnection);
      unawaited(feed.dispose());
    }
    _set(state.value.copyWith(realtime: false));
  }

  /// The positions are not arriving by themselves: no real-time connection,
  /// the trip is not in progress yet, or the bus has been silent for
  /// [silenceThreshold].
  bool get _needsPolling {
    final current = state.value;
    if (!current.realtime) return true;
    if (current.status != TripStatus.inProgress) return true;
    final seenAt = current.positionSeenAt;
    if (current.position == null || seenAt == null) return true;
    return _clock().difference(seenAt) >= silenceThreshold;
  }

  void _onConnection() {
    final connected = feed!.connected.value;
    _set(state.value.copyWith(realtime: connected));
    // Back after a drop: what was sent meanwhile is lost, ask for it.
    if (connected && _wasConnected) unawaited(refresh());
    if (connected) _wasConnected = true;
  }

  void _onLive(BusLocationUpdate update) {
    if (update.tripId != tripId) return;
    final current = state.value;
    if (!update.position.isNewerThan(current.position)) return; // late event
    _set(
      current.copyWith(
        phase: LiveTripPhase.tracking,
        // Positions are only broadcast while the trip is in progress.
        status: TripStatus.inProgress,
        position: update.position,
        positionSeenAt: _clock(),
        clearError: true,
      ),
    );
  }

  void _apply(TripTracking tracking) {
    final current = state.value;
    final position = tracking.position;
    final newer = position != null && position.isNewerThan(current.position);
    final finished = tracking.status.isFinished;

    _set(
      current.copyWith(
        phase: finished ? LiveTripPhase.finished : LiveTripPhase.tracking,
        status: tracking.status,
        position: newer ? position : null,
        positionSeenAt: newer
            ? _clock().subtract(Duration(seconds: tracking.ageSeconds ?? 0))
            : null,
        clearError: true,
      ),
    );
    if (finished) _stopFollowing();
  }

  void _set(LiveTripState value) {
    if (!_disposed) state.value = value;
  }
}
