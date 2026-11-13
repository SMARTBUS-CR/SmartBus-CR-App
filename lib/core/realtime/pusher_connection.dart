import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A text WebSocket, reduced to what [PusherConnection] needs (tests replace it).
abstract interface class RealtimeSocket {
  Stream<String> get messages;
  void send(String message);
  Future<void> close();
}

typedef RealtimeSocketConnector = Future<RealtimeSocket> Function(Uri uri);

/// Returns the signature (`auth`) to subscribe [channelName] with [socketId].
typedef ChannelAuthorizer = Future<String> Function(
  String socketId,
  String channelName,
);

enum RealtimeConnectionState { connecting, connected, disconnected }

/// An event received on a channel.
@immutable
class RealtimeEvent {
  const RealtimeEvent(this.channel, this.event, this.data);

  final String channel;
  final String event;

  /// Decoded `data` (Pusher sends it as a JSON string).
  final Map<String, dynamic> data;
}

/// A channel could not be subscribed (the authorization was refused, …).
@immutable
class RealtimeSubscriptionError {
  const RealtimeSubscriptionError(this.channel, this.error);

  final String channel;
  final Object error;
}

/// Default connector: `dart:io` [WebSocket] (no extra packages).
Future<RealtimeSocket> connectIoWebSocket(Uri uri) async =>
    _IoRealtimeSocket(await WebSocket.connect(uri.toString()));

class _IoRealtimeSocket implements RealtimeSocket {
  _IoRealtimeSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages => _socket.where((m) => m is String).cast();

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}

/// Minimal client of the **Pusher protocol** (v7), the one Laravel Reverb
/// speaks. Only what SmartBus uses: private channels and their events.
///
/// - `pusher:connection_established` → connected; (re)subscribes every channel.
/// - Private channels are authorized with [authorize] (the Gateway's
///   `broadcasting/auth`) before `pusher:subscribe`.
/// - Answers the server's `pusher:ping`, and pings the server itself when the
///   line is quiet for `activity_timeout`; no answer → reconnect.
/// - Reconnects by itself when the socket drops, waiting a bit longer each
///   time ([reconnectDelays]). Events sent while disconnected are lost
///   (Reverb keeps no history): listen to [state] to refresh on reconnect.
/// - **A channel only receives events once the server confirms it**
///   (`pusher_internal:subscription_succeeded`, see [subscribed]). An open
///   socket is not enough: if the signature request fails (the Gateway is
///   slow, a 5xx…) or the server answers `pusher:subscription_error`, the
///   subscription is tried again ([subscribeRetryDelays]) while the socket
///   stays open. Without this, one failed signature left the channel silent
///   for good and the passenger saw the bus only every 10–15 s (polling).
class PusherConnection {
  PusherConnection({
    required this.uri,
    required this.authorize,
    RealtimeSocketConnector? connector,
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
    this.subscribeRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
    this.pongTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 10),
  }) : _connector = connector ?? connectIoWebSocket;

  /// Waits between attempts to subscribe a channel that failed (the last one
  /// repeats). Reset when the channel is confirmed or the socket reconnects.
  final List<Duration> subscribeRetryDelays;

  /// Channels the server confirmed on the current socket: only these receive
  /// events. Emptied when the socket drops.
  final ValueNotifier<Set<String>> subscribed = ValueNotifier(const {});

  /// Max wait to open the socket. With a bad signal `WebSocket.connect` can
  /// hang for minutes; after this it counts as a failed attempt and the next
  /// reconnect is scheduled.
  final Duration connectTimeout;

  final Uri uri;
  final ChannelAuthorizer authorize;
  final RealtimeSocketConnector _connector;
  final List<Duration> reconnectDelays;

  /// How long to wait for any message after our `pusher:ping`.
  final Duration pongTimeout;

  final ValueNotifier<RealtimeConnectionState> state = ValueNotifier(
    RealtimeConnectionState.disconnected,
  );

  final StreamController<RealtimeEvent> _events = StreamController.broadcast();
  final StreamController<RealtimeSubscriptionError> _errors =
      StreamController.broadcast();

  /// Events of the subscribed channels (internal `pusher:*` ones excluded).
  Stream<RealtimeEvent> get events => _events.stream;

  /// Channels that could not be subscribed.
  Stream<RealtimeSubscriptionError> get subscriptionErrors => _errors.stream;

  final Set<String> _channels = {};
  RealtimeSocket? _socket;
  StreamSubscription<String>? _socketSub;
  String? _socketId;
  Timer? _reconnectTimer;
  Timer? _activityTimer;
  Duration _activityTimeout = const Duration(seconds: 120);
  bool _awaitingPong = false;
  int _attempt = 0;
  bool _wanted = false;
  bool _disposed = false;

  /// Pending re-subscription of a channel that failed, and how many times it
  /// failed in a row.
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _retryAttempts = {};

  /// Opens the connection (no-op when already open or opening).
  void connect() {
    if (_disposed) return;
    _wanted = true;
    if (_socket != null || state.value == RealtimeConnectionState.connecting) {
      return;
    }
    unawaited(_open());
  }

  /// Subscribes [channel] now if connected, and again after every reconnect.
  void subscribe(String channel) {
    if (!_channels.add(channel)) return;
    final socketId = _socketId;
    if (socketId != null) unawaited(_subscribe(channel, socketId));
  }

  void unsubscribe(String channel) {
    if (!_channels.remove(channel)) return;
    _cancelRetry(channel);
    _setSubscribed(channel, false);
    if (_socketId != null) {
      _send('pusher:unsubscribe', {'channel': channel});
    }
  }

  /// Closes the connection for good.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _wanted = false;
    _reconnectTimer?.cancel();
    await _drop();
    await _events.close();
    await _errors.close();
    state.dispose();
    subscribed.dispose();
  }

  // --- internals --------------------------------------------------------

  Future<void> _open() async {
    _setState(RealtimeConnectionState.connecting);
    try {
      final pending = _connector(uri);
      final socket = await pending.timeout(
        connectTimeout,
        onTimeout: () {
          // If it still opens later, close it: a new attempt takes over.
          pending.then((opened) => opened.close(), onError: (Object _) {});
          throw TimeoutException('WebSocket connect', connectTimeout);
        },
      );
      if (_disposed || !_wanted) {
        await socket.close();
        return;
      }
      _socket = socket;
      _socketSub = socket.messages.listen(
        _onMessage,
        onError: (Object _) => _onSocketClosed(),
        onDone: _onSocketClosed,
        cancelOnError: true,
      );
    } catch (_) {
      _onSocketClosed();
    }
  }

  void _onMessage(String raw) {
    _touch();
    final Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return; // not a Pusher message
    }
    final event = message['event'];
    final data = _decodeData(message['data']);

    switch (event) {
      case 'pusher:connection_established':
        _onEstablished(data);
      case 'pusher:ping':
        _send('pusher:pong', const {});
      case 'pusher:pong':
        break; // _touch() already reset the activity timer
      case 'pusher:error':
        _onServerError(data);
      case 'pusher_internal:subscription_succeeded':
        final channel = message['channel'];
        if (channel is String && _channels.contains(channel)) {
          _cancelRetry(channel);
          _retryAttempts.remove(channel);
          _setSubscribed(channel, true);
        }
      case 'pusher:subscription_error':
        // The server refused the subscription (e.g. a bad signature).
        final channel = message['channel'];
        if (channel is String && _channels.contains(channel)) {
          _onSubscribeFailed(channel, data);
        }
      case String name when !name.startsWith('pusher'):
        final channel = message['channel'];
        if (channel is String && _channels.contains(channel)) {
          _events.add(RealtimeEvent(channel, name, data));
        }
    }
  }

  void _onEstablished(Map<String, dynamic> data) {
    final socketId = data['socket_id'];
    if (socketId is! String) return;
    _socketId = socketId;
    final timeout = data['activity_timeout'];
    if (timeout is num && timeout > 0) {
      _activityTimeout = Duration(seconds: timeout.toInt());
    }
    _attempt = 0;
    _retryAttempts.clear(); // a new socket: start the waits again
    _touch();
    _setState(RealtimeConnectionState.connected);
    for (final channel in _channels.toList()) {
      unawaited(_subscribe(channel, socketId));
    }
  }

  /// Pusher error codes: 4000-4099 = do not reconnect (wrong key, …);
  /// anything else is handled by the reconnect of [_onSocketClosed].
  void _onServerError(Map<String, dynamic> data) {
    final code = data['code'];
    if (code is num && code >= 4000 && code < 4100) {
      _wanted = false;
      unawaited(_drop());
      _setState(RealtimeConnectionState.disconnected);
    }
  }

  Future<void> _subscribe(String channel, String socketId) async {
    try {
      final auth = channel.startsWith('private-')
          ? await authorize(socketId, channel)
          : null;
      // The socket may have changed while waiting for the signature.
      if (_socketId != socketId || !_channels.contains(channel)) return;
      _send('pusher:subscribe', {'channel': channel, 'auth': ?auth});
    } catch (error) {
      if (_socketId != socketId || !_channels.contains(channel)) return;
      _onSubscribeFailed(channel, error);
    }
  }

  /// [channel] could not be subscribed: reported, and tried again after a
  /// growing wait while this socket stays open (a new socket subscribes every
  /// channel anyway).
  void _onSubscribeFailed(String channel, Object error) {
    if (!_errors.isClosed) {
      _errors.add(RealtimeSubscriptionError(channel, error));
    }
    if (_disposed || subscribeRetryDelays.isEmpty) return;
    final attempt = _retryAttempts[channel] ?? 0;
    _retryAttempts[channel] = attempt + 1;
    final delay =
        subscribeRetryDelays[attempt.clamp(0, subscribeRetryDelays.length - 1)];
    final socketId = _socketId;
    _cancelRetry(channel);
    _retryTimers[channel] = Timer(delay, () {
      _retryTimers.remove(channel);
      if (_disposed ||
          socketId == null ||
          _socketId != socketId ||
          !_channels.contains(channel) ||
          subscribed.value.contains(channel)) {
        return;
      }
      unawaited(_subscribe(channel, socketId));
    });
  }

  void _cancelRetry(String channel) => _retryTimers.remove(channel)?.cancel();

  void _setSubscribed(String channel, bool value) {
    if (_disposed || subscribed.value.contains(channel) == value) return;
    subscribed.value = value
        ? {...subscribed.value, channel}
        : ({...subscribed.value}..remove(channel));
  }

  void _send(String event, Map<String, dynamic> data) {
    _socket?.send(jsonEncode({'event': event, 'data': data}));
  }

  /// Any message from the server proves the line is alive.
  void _touch() {
    _awaitingPong = false;
    _activityTimer?.cancel();
    _activityTimer = Timer(_activityTimeout, _onQuiet);
  }

  void _onQuiet() {
    if (_awaitingPong) {
      // No answer to our ping: the connection is dead but nobody told us.
      unawaited(_drop().then((_) => _onSocketClosed()));
      return;
    }
    _awaitingPong = true;
    _send('pusher:ping', const {});
    _activityTimer = Timer(pongTimeout, _onQuiet);
  }

  void _onSocketClosed() {
    unawaited(_drop());
    if (_disposed) return;
    _setState(RealtimeConnectionState.disconnected);
    if (!_wanted) return;
    final delay =
        reconnectDelays[_attempt.clamp(0, reconnectDelays.length - 1)];
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_wanted && !_disposed && _socket == null) unawaited(_open());
    });
  }

  Future<void> _drop() async {
    _activityTimer?.cancel();
    _activityTimer = null;
    _socketId = null;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    // A new socket must be confirmed again.
    if (!_disposed && subscribed.value.isNotEmpty) subscribed.value = const {};
    final sub = _socketSub;
    final socket = _socket;
    _socketSub = null;
    _socket = null;
    if (sub != null) unawaited(sub.cancel());
    try {
      await socket?.close();
    } catch (_) {
      // already closed
    }
  }

  void _setState(RealtimeConnectionState value) {
    if (!_disposed) state.value = value;
  }

  static Map<String, dynamic> _decodeData(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // plain text data: ignored
      }
    }
    return const {};
  }
}
