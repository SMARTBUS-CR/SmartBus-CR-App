import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/realtime/pusher_connection.dart';
import 'package:smartbus_drivers/features/trip_tracking/models/trip_tracking.dart';
import 'package:smartbus_drivers/features/trip_tracking/services/trip_live_feed.dart';

const _tripId = '01a09332-3457-7315-885e-4ebb218f7262';
final _channel = ReverbTripFeed.channelFor(_tripId);

/// Fake server side of the WebSocket.
class _FakeSocket implements RealtimeSocket {
  final StreamController<String> _incoming = StreamController();
  final List<String> sentEvents = [];

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) =>
      sentEvents.add((jsonDecode(message) as Map)['event'] as String);

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  void serverSends(String event, Map<String, dynamic> data, {String? channel}) {
    _incoming.add(
      jsonEncode({
        'event': event,
        'data': jsonEncode(data),
        'channel': ?channel,
      }),
    );
  }
}

void main() {
  late List<_FakeSocket> sockets;
  late int authFailures;

  ReverbTripFeed buildFeed() {
    sockets = [];
    return ReverbTripFeed(
      PusherConnection(
        uri: Uri.parse('wss://gateway.test/app/key'),
        authorize: (_, _) async {
          if (authFailures-- > 0) throw StateError('503');
          return 'key:signature';
        },
        connector: (uri) async {
          final socket = _FakeSocket();
          sockets.add(socket);
          return socket;
        },
      ),
    );
  }

  setUp(() => authFailures = 0);

  test('"connected" (live) only after the trip channel is confirmed', () {
    fakeAsync((async) {
      final feed = buildFeed()..follow(_tripId);
      async.flushMicrotasks();
      sockets.single.serverSends('pusher:connection_established', {
        'socket_id': '1.1',
        'activity_timeout': 30,
      });
      async.flushMicrotasks();

      // The socket is open, but the channel is not confirmed: not live.
      expect(feed.connected.value, isFalse);

      sockets.single.serverSends(
        'pusher_internal:subscription_succeeded',
        {},
        channel: _channel,
      );
      async.flushMicrotasks();
      expect(feed.connected.value, isTrue);
      feed.dispose();
    });
  });

  test('a failed signature leaves it not live until the retry succeeds, '
      'then the bus positions arrive', () {
    fakeAsync((async) {
      authFailures = 1;
      final positions = <BusLocationUpdate>[];
      final feed = buildFeed()..follow(_tripId);
      feed.locations.listen(positions.add);
      async.flushMicrotasks();
      sockets.single.serverSends('pusher:connection_established', {
        'socket_id': '1.1',
        'activity_timeout': 30,
      });
      async.flushMicrotasks();
      expect(sockets.single.sentEvents, isEmpty); // the signature failed
      expect(feed.connected.value, isFalse);

      async.elapse(const Duration(seconds: 2)); // retried on the same socket
      expect(sockets.single.sentEvents, ['pusher:subscribe']);
      sockets.single
        ..serverSends(
          'pusher_internal:subscription_succeeded',
          {},
          channel: _channel,
        )
        ..serverSends('BusLocationUpdated', {
          'trip_id': _tripId,
          'bus_id': 'bus',
          'latitude': 9.93,
          'longitude': -84.08,
          'recorded_at': '2026-11-12T15:00:00Z',
        }, channel: _channel);
      async.flushMicrotasks();

      expect(feed.connected.value, isTrue);
      expect(positions.single.position.latitude, 9.93);
      feed.dispose();
    });
  });

  test('TripArrivalsUpdated event is parsed and emitted', () {
    fakeAsync((async) {
      final arrivals = <Map<String, dynamic>>[];
      final feed = buildFeed()..follow(_tripId);
      feed.arrivals.listen(arrivals.add);
      async.flushMicrotasks();

      sockets.single.serverSends('pusher:connection_established', {
        'socket_id': '1.1',
        'activity_timeout': 30,
      });
      async.flushMicrotasks();

      sockets.single
        ..serverSends(
          'pusher_internal:subscription_succeeded',
          {},
          channel: _channel,
        )
        ..serverSends('TripArrivalsUpdated', {
          'arrivals': [
            {
              'stop_occurrence_id': 'occ-1',
              'stop_id': 'stop-1',
              'stop_sequence': 1,
              'eta_seconds': 120,
              'method': 'ml',
            }
          ]
        }, channel: _channel);
      async.flushMicrotasks();

      expect(arrivals, hasLength(1));
      expect(arrivals.single['stop-1']?.etaMinutes, 2);
      feed.dispose();
    });
  });
}
