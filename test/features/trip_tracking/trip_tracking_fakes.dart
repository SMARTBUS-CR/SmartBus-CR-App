import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/gps_fix.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/gps_location_service.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/live_trip_tracker.dart';

/// GPS service with one canned [TripTracking] per trip.
class FakeGps implements GpsLocationService {
  FakeGps([Map<String, TripTracking>? trips]) : trips = trips ?? {};

  final Map<String, TripTracking> trips;
  ApiException? error;
  final List<String> asked = [];

  @override
  Future<TripTracking> latestForTrip(String tripId) async {
    asked.add(tripId);
    if (error != null) throw error!;
    final tracking = trips[tripId];
    if (tracking == null) {
      throw const ApiException(ApiErrorType.notFound, 'Viaje no encontrado.');
    }
    return tracking;
  }

  @override
  Future<String?> send(GpsFix fix) => throw UnimplementedError();

  @override
  Future<String> authorizeChannel({
    required String socketId,
    required String channelName,
  }) => throw UnimplementedError();
}

/// A trip in progress with the bus at [lat], [lng], [ageSeconds] old.
TripTracking inProgressAt(
  String tripId,
  double lat,
  double lng, {
  int ageSeconds = 2,
}) => TripTracking(
  tripId: tripId,
  status: TripStatus.inProgress,
  freshness: TrackingFreshness.live,
  ageSeconds: ageSeconds,
  position: BusPosition(
    latitude: lat,
    longitude: lng,
    recordedAt: DateTime.utc(2026, 11, 11, 15),
  ),
);

TripTracking finishedTrip(String tripId) => TripTracking(
  tripId: tripId,
  status: TripStatus.completed,
  freshness: TrackingFreshness.notTracking,
);

/// Trackers over [gps] without real time (they poll), keeping every one built.
class FakeTrackers {
  FakeTrackers(this.gps, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final FakeGps gps;
  final DateTime Function() clock;
  final List<LiveTripTracker> built = [];

  LiveTripTracker call(String tripId) {
    final tracker = LiveTripTracker(tripId: tripId, service: gps, clock: clock);
    built.add(tracker);
    return tracker;
  }
}
