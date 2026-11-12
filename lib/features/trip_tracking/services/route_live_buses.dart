import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../operations/models/operations_models.dart';
import '../../operations/services/operations_service.dart';
import 'live_trip_tracker.dart';

/// A bus running on the pattern, with what its tracker knows right now.
@immutable
class LiveBus {
  const LiveBus({required this.trip, required this.state});

  /// The trip from the Dashboard (bus unit / plate, departure).
  final LiveBusTrip trip;

  /// Status and position from the GPS service (see [LiveTripTracker]).
  final LiveTripState state;
}

/// What the passenger home shows for the selected direction.
@immutable
class RouteLiveBusesState {
  const RouteLiveBusesState({
    this.loading = true,
    this.buses = const [],
    this.error,
  });

  /// The first list of buses has not arrived yet.
  final bool loading;

  /// Buses running now, in the Dashboard order. Finished trips are left out.
  final List<LiveBus> buses;

  /// Message of the last failed request to the Dashboard, or `null`.
  final String? error;
}

/// Follows **every bus running** on one route pattern, for the home map.
///
/// 1. `GET ops/route-patterns/{id}/trips` (only `in_progress`, i.e. the driver
///    tapped "Iniciar recorrido") → one [LiveTripTracker] per trip, the same
///    one "Rastreando tu bus" uses (GET + real-time `BusLocationUpdated`).
/// 2. Asks the Dashboard again every [refreshEvery]: new trips get a tracker,
///    trips no longer running lose theirs.
/// 3. A trip whose tracker says it finished (or does not exist) disappears
///    right away, without waiting for the next refresh.
class RouteLiveBuses {
  RouteLiveBuses({
    required this.patternId,
    required this.operations,
    LiveTripTrackerFactory? trackerFactory,
    this.refreshEvery = const Duration(seconds: 30),
  }) : _trackerFactory = trackerFactory ?? LiveTripTracker.withDefaults;

  final String patternId;
  final Duration refreshEvery;
  final OperationsService operations;
  final LiveTripTrackerFactory _trackerFactory;

  final ValueNotifier<RouteLiveBusesState> state = ValueNotifier(
    const RouteLiveBusesState(),
  );

  /// Trips in the Dashboard order, and the tracker of each one.
  List<LiveBusTrip> _trips = const [];
  final Map<String, LiveTripTracker> _trackers = {};
  Timer? _timer;
  bool _syncing = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) return;
    await refresh();
    if (_disposed) return;
    _timer ??= Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
  }

  /// Asks the Dashboard which trips are running on the pattern now.
  Future<void> refresh() async {
    if (_syncing || _disposed) return;
    _syncing = true;
    try {
      final trips = await operations.ongoingTrips(patternId);
      if (_disposed) return;
      _sync(trips);
      _publish(error: null);
    } on ApiException catch (e) {
      // Keep the buses already on the map; they keep updating by themselves.
      _publish(error: e.message);
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    for (final tracker in _trackers.values) {
      _close(tracker);
    }
    _trackers.clear();
    state.dispose();
  }

  // --- internals ------------------------------------------------------------

  void _sync(List<LiveBusTrip> trips) {
    _trips = trips;
    final ids = {for (final trip in trips) trip.id};
    for (final id in _trackers.keys.toList()) {
      if (!ids.contains(id)) _close(_trackers.remove(id)!);
    }
    for (final trip in trips) {
      if (_trackers.containsKey(trip.id)) continue;
      final tracker = _trackerFactory(trip.id);
      _trackers[trip.id] = tracker;
      tracker.state.addListener(_onTrackerChanged);
      unawaited(tracker.start());
    }
  }

  void _close(LiveTripTracker tracker) {
    tracker.state.removeListener(_onTrackerChanged);
    tracker.dispose();
  }

  void _onTrackerChanged() => _publish();

  void _publish({Object? error = _keep}) {
    if (_disposed) return;
    final buses = <LiveBus>[];
    for (final trip in _trips) {
      final tracker = _trackers[trip.id];
      if (tracker == null) continue;
      final tripState = tracker.state.value;
      // Finished or unknown to the GPS service: nothing to show.
      if (tripState.phase == LiveTripPhase.finished ||
          tripState.phase == LiveTripPhase.notFound) {
        continue;
      }
      buses.add(LiveBus(trip: trip, state: tripState));
    }
    state.value = RouteLiveBusesState(
      loading: false,
      buses: buses,
      error: identical(error, _keep) ? state.value.error : error as String?,
    );
  }

  static const Object _keep = Object();
}
