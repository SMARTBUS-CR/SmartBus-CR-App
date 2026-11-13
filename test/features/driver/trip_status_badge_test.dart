import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/theme.dart';
import 'package:smartbus_drivers/features/driver/widgets/trip_status_badge.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_location_sender.dart';

import '../operations/operations_fixtures.dart';

TripTrackingSnapshot _gps(
  TripTrackingState state, {
  String? trip = tripId,
  DateTime? lastSentAt,
  String? lastError,
}) => TripTrackingSnapshot(
  state: state,
  tripId: trip,
  lastSentAt: lastSentAt,
  lastError: lastError,
);

void main() {
  group('TripStatusInfo (the status table of the story)', () {
    final now = DateTime(2026, 11, 12, 10);
    const idle = TripTrackingSnapshot();

    test('scheduled → Programado, blue, "Listo para iniciar"', () {
      final info = TripStatusInfo.of(driverTrip(status: 'scheduled'), idle);
      expect(info.label, 'Programado');
      expect(info.color, SmartBusColors.azulPrincipal);
      expect(info.message, 'Listo para iniciar');
    });

    test(
      'in progress + sending → En curso, green, last confirmed location',
      () {
        final info = TripStatusInfo.of(
          driverTrip(status: 'in_progress'),
          _gps(
            TripTrackingState.tracking,
            lastSentAt: now.subtract(const Duration(seconds: 12)),
          ),
          now: now,
        );
        expect(info.label, 'En curso');
        expect(info.color, SmartBusColors.verdeMenta);
        expect(info.message, 'Enviando ubicación · última hace 12 s');
      },
    );

    test('in progress + stopped → orange "ubicación detenida"', () {
      for (final snap in [
        idle, // reopened the app
        _gps(TripTrackingState.stopped),
        _gps(TripTrackingState.permissionDenied),
        _gps(TripTrackingState.locationServicesDisabled),
        _gps(TripTrackingState.tracking, trip: 'other-trip'),
      ]) {
        final info = TripStatusInfo.of(driverTrip(status: 'in_progress'), snap);
        expect(info.label, 'En curso · ubicación detenida', reason: '$snap');
        expect(info.color, SmartBusColors.retraso);
        expect(info.message, 'No se está enviando tu ubicación');
      }
    });

    test(
      'in progress + rejected → red "ubicación rechazada" with the reason',
      () {
        final info = TripStatusInfo.of(
          driverTrip(status: 'in_progress'),
          _gps(TripTrackingState.rejected, lastError: 'No eres el conductor.'),
        );
        expect(info.label, 'En curso · ubicación rechazada');
        expect(info.color, SmartBusColors.error);
        expect(info.message, 'No eres el conductor.');
      },
    );

    test('completed → Finalizado with the arrival time (local)', () {
      final info = TripStatusInfo.of(
        driverTrip(status: 'completed', actualArrivalAt: completedArrivalAt),
        idle,
      );
      final arrival = formatHour(DateTime.parse(completedArrivalAt));
      expect(info.label, 'Finalizado');
      expect(info.color, tripStatusBadge(TripStatus.completed).$2);
      expect(info.message, 'Recorrido finalizado · llegada $arrival');
    });

    test('cancelled → Cancelado, red, "Este viaje fue cancelado"', () {
      final info = TripStatusInfo.of(driverTrip(status: 'cancelled'), idle);
      expect(info.label, 'Cancelado');
      expect(info.color, SmartBusColors.error);
      expect(info.message, 'Este viaje fue cancelado');
    });

    test('last confirmed location labels', () {
      expect(TripStatusInfo.lastSentLabel(null, now), 'sin confirmar');
      expect(TripStatusInfo.lastSentLabel(now, now), 'última hace un momento');
      expect(
        TripStatusInfo.lastSentLabel(
          now.subtract(const Duration(minutes: 3, seconds: 5)),
          now,
        ),
        'última hace 3 min',
      );
    });
  });

  group('DriverTrip.refreshedWith', () {
    test('takes the new status and times, keeps what the refresh lacks', () {
      final shown = DriverTrip.fromJsonApi(
        tripResource(status: 'in_progress', withRelationships: true),
        included: JsonApiIncluded(driverTripsIncluded()),
      );
      // GET ops/trips/{id}: no include, no snapshot.
      final fresh = DriverTrip.fromJsonApi(
        tripResource(
          status: 'completed',
          snapshot: null,
          actualArrivalAt: completedArrivalAt,
        ),
      );

      final merged = shown.refreshedWith(fresh);

      expect(merged.status, TripStatus.completed);
      expect(
        merged.actualArrivalAt!.isAtSameMomentAs(
          DateTime.parse(completedArrivalAt),
        ),
        isTrue,
      );
      expect(merged.busLabel, 'Bus SJB-1234 · Unidad 07');
      expect(merged.title, 'PV-RF · Puerto Viejo');
      expect(merged.headsign, 'Puerto Viejo');
    });
  });

  testWidgets('the Inicio badge has text, icon and a semantics label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: TripStatusBadge.forStatus(TripStatus.cancelled)),
        ),
      ),
    );

    expect(find.text('Cancelado'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('Estado del viaje: Cancelado'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
