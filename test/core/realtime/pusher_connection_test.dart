import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/realtime/pusher_connection.dart';

/// Fake server side of the WebSocket.
class _FakeSocket implements RealtimeSocket {
  final StreamController<String> _incoming = StreamController();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) =>
      sent.add(Map<String, dynamic>.from(jsonDecode(message) as Map));

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  /// The server sends a Pusher message (`data` as a JSON string, like Reverb).
  void serverSends(String event, Map<String, dynamic> data, {String? channel}) {
    _incoming.add(
      jsonEncode({
        'event': event,
        'data': jsonEncode(data),
        'channel': ?channel,
      }),
    );
  }

  void establish([String socketId = '123.456']) => serverSends(
    'pusher:connection_established',
    {'socket_id': socketId, 'activity_timeout': 30},
  );

  /// The network drops.
  void drop() => _incoming.close();

  List<String> get sentEvents => sent.map((m) => m['event'] as String).toList();
}

const _channel = 'private-trip.01a09332-3457-7315-885e-4ebb218f7262';

void main() {
  late List<_FakeSocket> sockets;
  late List<(String, String)> authorizations;
  late PusherConnection connection;

  setUp(() {
    sockets = [];
    authorizations = [];
    connection = PusherConnection(
      uri: Uri.parse('wss://gateway.test/app/key?protocol=7'),
      authorize: (socketId, channel) async {
        authorizations.add((socketId, channel));
        return 'key:signature';
      },
      connector: (uri) async {
        final socket = _FakeSocket();
        sockets.add(socket);
        return socket;
      },
    );
  });

  test('subscribes a private channel with the Gateway signature', () {
    fakeAsync((async) {
      connection
        ..subscribe(_channel)
        ..connect();
      async.flushMicrotasks();
      expect(connection.state.value, RealtimeConnectionState.connecting);

      sockets.single.establish('99.1');
      async.flushMicrotasks();

      expect(connection.state.value, RealtimeConnectionState.connected);
      expect(authorizations, [('99.1', _channel)]);
      expect(sockets.single.sent.single, {
        'event': 'pusher:subscribe',
        'data': {'channel': _channel, 'auth': 'key:signature'},
      });
    });
  });

  test('delivers the channel events with their data decoded', () {
    fakeAsync((async) {
      final events = <RealtimeEvent>[];
      connection.events.listen(events.add);
      connection
        ..subscribe(_channel)
        ..connect();
      async.flushMicrotasks();
      sockets.single.establish();
      async.flushMicrotasks();

      sockets.single
        ..serverSends(
          'pusher_internal:subscription_succeeded',
          {},
          channel: _channel,
        )
        ..serverSends('BusLocationUpdated', {
          'latitude': 9.93,
        }, channel: _channel)
        ..serverSends('BusLocationUpdated', {'latitude': 1}, channel: 'other');
      async.flushMicrotasks();

      expect(events, hasLength(1));
      expect(events.single.event, 'BusLocationUpdated');
      expect(events.single.channel, _channel);
      expect(events.single.data, {'latitude': 9.93});
    });
  });

  test('answers the server ping', () {
    fakeAsync((async) {
      connection.connect();
      async.flushMicrotasks();
      sockets.single
        ..establish()
        ..serverSends('pusher:ping', {});
      async.flushMicrotasks();

      expect(sockets.single.sentEvents, ['pusher:pong']);
    });
  });

  test('reconnects after a drop and subscribes the channel again', () {
    fakeAsync((async) {
      final states = <RealtimeConnectionState>[];
      connection.state.addListener(() => states.add(connection.state.value));
      connection
        ..subscribe(_channel)
        ..connect();
      async.flushMicrotasks();
      sockets.single.establish('1.1');
      async.flushMicrotasks();

      sockets.single.drop();
      async.flushMicrotasks();
      expect(connection.state.value, RealtimeConnectionState.disconnected);

      async.elapse(const Duration(seconds: 1)); // first reconnect delay
      expect(sockets, hasLength(2));
      sockets.last.establish('2.2');
      async.flushMicrotasks();

      expect(connection.state.value, RealtimeConnectionState.connected);
      expect(authorizations.last, ('2.2', _channel));
      expect(sockets.last.sentEvents, ['pusher:subscribe']);
      expect(states, [
        RealtimeConnectionState.connecting,
        RealtimeConnectionState.connected,
        RealtimeConnectionState.disconnected,
        RealtimeConnectionState.connecting,
        RealtimeConnectionState.connected,
      ]);
    });
  });

  test('a quiet line is checked with a ping; no answer -> reconnect', () {
    fakeAsync((async) {
      connection.connect();
      async.flushMicrotasks();
      sockets.single.establish(); // activity_timeout = 30 s
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));
      expect(sockets.single.sentEvents, ['pusher:ping']);

      async.elapse(const Duration(seconds: 30)); // pongTimeout, no answer
      expect(sockets.first.closed, isTrue);
      expect(connection.state.value, RealtimeConnectionState.disconnected);

      async.elapse(const Duration(seconds: 1));
      expect(sockets, hasLength(2));
    });
  });

  test('a refused authorization is reported, not sent', () {
    fakeAsync((async) {
      final errors = <RealtimeSubscriptionError>[];
      final refusing = PusherConnection(
        uri: Uri.parse('wss://gateway.test/app/key'),
        authorize: (_, _) async => throw StateError('403'),
        connector: (uri) async {
          final socket = _FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
      refusing.subscriptionErrors.listen(errors.add);
      refusing
        ..subscribe(_channel)
        ..connect();
      async.flushMicrotasks();
      sockets.single.establish();
      async.flushMicrotasks();

      expect(errors.single.channel, _channel);
      expect(sockets.single.sent, isEmpty);
      refusing.dispose();
    });
  });

  test('error 4001 (wrong app key) does not reconnect', () {
    fakeAsync((async) {
      connection.connect();
      async.flushMicrotasks();
      sockets.single.serverSends('pusher:error', {
        'code': 4001,
        'message': 'Application does not exist',
      });
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(sockets, hasLength(1));
      expect(connection.state.value, RealtimeConnectionState.disconnected);
    });
  });

  test('dispose closes the socket and stops reconnecting', () {
    fakeAsync((async) {
      connection.connect();
      async.flushMicrotasks();
      sockets.single.establish();
      async.flushMicrotasks();

      connection.dispose();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(sockets.single.closed, isTrue);
      expect(sockets, hasLength(1));
    });
  });
}
