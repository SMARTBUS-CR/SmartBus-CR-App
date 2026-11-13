import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_arrival_estimate.dart';

void main() {
  group('TripArrivalEstimate.fromJson', () {
    test('parses complete snake_case json', () {
      final json = {
        'occurrence_id': 'occ-123',
        'stop_id': 'stop-456',
        'stop_sequence': 3,
        'eta_seconds': 175,
        'arrival_at': '2026-11-13T12:30:00.000Z',
        'method': 'ml',
      };

      final estimate = TripArrivalEstimate.fromJson(json);

      expect(estimate.occurrenceId, 'occ-123');
      expect(estimate.stopId, 'stop-456');
      expect(estimate.stopSequence, 3);
      expect(estimate.etaSeconds, 175);
      expect(estimate.etaMinutes, 3); // 175 / 60 = 2.916 -> 3
      expect(estimate.arrivalAt, DateTime.parse('2026-11-13T12:30:00.000Z').toLocal());
      expect(estimate.method, 'ml');
      expect(estimate.isLive, isTrue);
    });

    test('parses stop_occurrence_id and camelCase alternatives', () {
      final json = {
        'stop_occurrence_id': 'occ-789',
        'stopId': 'stop-999',
        'stopSequence': 5,
        'etaSeconds': 90,
        'arrivalAt': '2026-11-13T14:00:00.000Z',
        'method': 'fallback',
      };

      final estimate = TripArrivalEstimate.fromJson(json);

      expect(estimate.occurrenceId, 'occ-789');
      expect(estimate.stopId, 'stop-999');
      expect(estimate.stopSequence, 5);
      expect(estimate.etaSeconds, 90);
      expect(estimate.etaMinutes, 2); // 90 / 60 = 1.5 -> 2
      expect(estimate.isLive, isTrue);
    });

    test('handles null eta and arrival_at with scheduled method', () {
      final json = {
        'occurrence_id': 'occ-1',
        'stop_id': 'stop-1',
        'stop_sequence': 1,
        'eta_seconds': null,
        'arrival_at': null,
        'method': 'scheduled_reference',
      };

      final estimate = TripArrivalEstimate.fromJson(json);

      expect(estimate.etaSeconds, isNull);
      expect(estimate.etaMinutes, isNull);
      expect(estimate.arrivalAt, isNull);
      expect(estimate.method, 'scheduled_reference');
      expect(estimate.isLive, isFalse);
    });

    test('isLive is true only for ml and fallback', () {
      expect(
        TripArrivalEstimate(
          occurrenceId: '1',
          stopId: '1',
          stopSequence: 1,
          method: 'ml',
        ).isLive,
        isTrue,
      );
      expect(
        TripArrivalEstimate(
          occurrenceId: '1',
          stopId: '1',
          stopSequence: 1,
          method: 'fallback',
        ).isLive,
        isTrue,
      );
      expect(
        TripArrivalEstimate(
          occurrenceId: '1',
          stopId: '1',
          stopSequence: 1,
          method: 'scheduled_reference',
        ).isLive,
        isFalse,
      );
      expect(
        TripArrivalEstimate(
          occurrenceId: '1',
          stopId: '1',
          stopSequence: 1,
          method: 'unavailable',
        ).isLive,
        isFalse,
      );
    });
  });

  group('parseArrivals', () {
    test('extracts arrivals from standard map with arrivals key', () {
      final data = {
        'arrivals': [
          {
            'stop_occurrence_id': 'occ-1',
            'stop_id': 'stop-1',
            'stop_sequence': 1,
            'eta_seconds': 120,
            'method': 'ml',
          },
        ],
      };

      final map = parseArrivals(data);

      expect(map.containsKey('stop-1'), isTrue);
      expect(map.containsKey('occ-1'), isTrue);
      expect(map['stop-1']!.etaMinutes, 2);
    });

    test('extracts arrivals from JSON:API data.attributes.arrivals', () {
      final data = {
        'data': {
          'attributes': {
            'arrivals': [
              {
                'stop_occurrence_id': 'occ-2',
                'stop_id': 'stop-2',
                'stop_sequence': 2,
                'eta_seconds': 300,
                'method': 'scheduled_reference',
              },
            ],
          },
        },
      };

      final map = parseArrivals(data);

      expect(map['stop-2']!.etaMinutes, 5);
      expect(map['occ-2']!.isLive, isFalse);
    });

    test('handles empty or null gracefully', () {
      expect(parseArrivals(null), isEmpty);
      expect(parseArrivals({}), isEmpty);
      expect(parseArrivals('invalid json'), isEmpty);
    });
  });
}
