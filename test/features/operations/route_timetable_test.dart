import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/operations/models/route_timetable.dart';

void main() {
  group('RouteFare', () {
    test('reads the Dashboard resource (amount as a string)', () {
      final fare = RouteFare.fromJsonApi({
        'id': 'f1',
        'type': 'route-fares',
        'attributes': {
          'amount': '1570.00',
          'currency': 'CRC',
          'valid_from': null,
          'valid_until': null,
        },
      });
      expect(fare.amount, 1570);
      expect(fare.label, '₡1.570');
    });

    test('formats colones and other currencies', () {
      expect(formatMoney(650, 'CRC'), '₡650');
      expect(formatMoney(1570, 'CRC'), '₡1.570');
      expect(formatMoney(1250000, 'CRC'), '₡1.250.000');
      expect(formatMoney(1570.5, 'CRC'), '₡1.570,50');
      expect(formatMoney(2.5, 'USD'), 'USD 2,50');
    });

    test('fareOn picks the one valid that day (the newest when several)', () {
      final fares = [
        RouteFare(
          amount: 1400,
          currency: 'CRC',
          validUntil: DateTime(2026, 10, 31),
        ),
        RouteFare(
          amount: 1570,
          currency: 'CRC',
          validFrom: DateTime(2026, 11, 1),
        ),
      ];
      expect(fareOn(fares, DateTime(2026, 10, 15))?.amount, 1400);
      expect(fareOn(fares, DateTime(2026, 11, 12, 18))?.amount, 1570);
      expect(fareOn(const [], DateTime(2026, 11, 12)), isNull);
    });
  });

  group('RouteSchedule', () {
    Map<String, dynamic> resource({
      int day = 4,
      String time = '06:00:00',
      List<String> suspended = const [],
      String? from,
      String? until,
    }) => {
      'id': 's',
      'type': 'route-schedules',
      'attributes': {
        'day_of_week': day,
        'departure_time': time,
        'valid_from': from,
        'valid_until': until,
        'suspended_dates': suspended,
      },
    };

    test('reads the departure time', () {
      final schedule = RouteSchedule.fromJsonApi(resource(time: '10:30:00'));
      expect(schedule.label, '10:30');
      expect(schedule.minutesOfDay, 630);
    });

    test('day_of_week: 0 = Sunday … 6 = Saturday', () {
      // 2026-11-12 is a Thursday (4); 2026-11-15 a Sunday (0).
      expect(
        RouteSchedule.fromJsonApi(resource(day: 4))
            .runsOn(DateTime(2026, 11, 12)),
        isTrue,
      );
      expect(
        RouteSchedule.fromJsonApi(resource(day: 0))
            .runsOn(DateTime(2026, 11, 15)),
        isTrue,
      );
      expect(
        RouteSchedule.fromJsonApi(resource(day: 0))
            .runsOn(DateTime(2026, 11, 12)),
        isFalse,
      );
    });

    test('a suspended date or outside its validity: it does not run', () {
      final thursday = DateTime(2026, 11, 12, 9);
      expect(
        RouteSchedule.fromJsonApi(resource(suspended: ['2026-11-12']))
            .runsOn(thursday),
        isFalse,
      );
      expect(
        RouteSchedule.fromJsonApi(resource(from: '2026-12-01'))
            .runsOn(thursday),
        isFalse,
      );
      expect(
        RouteSchedule.fromJsonApi(resource(until: '2026-11-11'))
            .runsOn(thursday),
        isFalse,
      );
    });

    test('departuresOn: only that day, earliest first', () {
      final schedules = [
        RouteSchedule.fromJsonApi(resource(time: '12:00:00')),
        RouteSchedule.fromJsonApi(resource(day: 5, time: '07:00:00')),
        RouteSchedule.fromJsonApi(resource(time: '06:00:00')),
      ];
      expect(
        departuresOn(schedules, DateTime(2026, 11, 12)).map((s) => s.label),
        ['06:00', '12:00'],
      );
    });
  });
}
