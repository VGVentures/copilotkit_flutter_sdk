// Minimal Phoenix channels v2 client for the Intelligence spike (#72).
//
// Candidate for replacing `phoenix_socket`: it covers what the Intelligence
// run needs (join, heartbeat with a reply timeout, push/reply, server events,
// close) in one class on top of `web_socket_channel`.
//
// It does not reconnect. The join token is single-use, so a reconnect needs
// fresh credentials from the runtime and a cursor to resume from, which is the
// transport's job (docs/adr/0012).
//
// Wire format (vsn=2.0.0): every frame is the JSON array
//   [join_ref, ref, topic, event, payload]

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One server-pushed frame.
class const PhoenixEvent({
  required final String topic,
  required final String event,
  required final Map<String, Object?> payload,
});

/// Thrown when the server answers a join or push with `status: error`.
class const PhoenixReplyException(final String event, final Object? response)
    implements Exception {
  @override
  String toString() => 'PhoenixReplyException($event): $response';
}

/// A Phoenix socket joined to a single channel topic.
class PhoenixClient({
  required Uri clientUrl,
  required Map<String, String> params,
  final Duration heartbeatInterval = const Duration(seconds: 30),
  final Duration replyTimeout = const Duration(seconds: 10),
  WebSocketChannel Function(Uri)? connect,
}) {
  /// Creates a client for the socket at [clientUrl], sending [params] with the
  /// handshake.
  this;

  final Uri _url = _socketUrl(clientUrl, params);
  final WebSocketChannel Function(Uri) _connect =
      connect ?? WebSocketChannel.connect;

  final _events = StreamController<PhoenixEvent>.broadcast();
  final _pending = <String, Completer<Object?>>{};
  WebSocketChannel? _channel;
  Timer? _heartbeat;
  int _ref = 0;
  String? _joinRef;

  /// Server-pushed events (not replies), for every joined topic.
  Stream<PhoenixEvent> get events => _events.stream;

  /// Opens the socket. Throws if the handshake fails (bad token, bad URL).
  Future<void> open() async {
    final channel = _connect(_url);
    _channel = channel;
    await channel.ready;
    channel.stream.listen(
      _onFrame,
      onError: _events.addError,
      onDone: _onClosed,
    );
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      unawaited(
        _push(
          topic: 'phoenix',
          event: 'heartbeat',
          payload: const {},
          joinRef: null,
        ).catchError((Object error) {
          // No answer in time: the connection is half-open, so report it and
          // drop it, the way a closed socket is reported.
          if (!_events.isClosed) _events.addError(error);
          unawaited(_channel?.sink.close());
          return null;
        }),
      );
    });
  }

  /// Joins [topic] and returns the join reply's `response`.
  Future<Object?> join(String topic, Map<String, Object?> params) {
    _joinRef = '${_ref + 1}';
    return _push(
      topic: topic,
      event: 'phx_join',
      payload: params,
      joinRef: _joinRef,
    );
  }

  /// Pushes [event] on [topic] and waits for the reply.
  Future<Object?> push(
    String topic,
    String event,
    Map<String, Object?> payload,
  ) => _push(topic: topic, event: event, payload: payload, joinRef: _joinRef);

  /// Closes the socket and fails the pushes still waiting for a reply. Safe to
  /// call twice.
  Future<void> close() async {
    _heartbeat?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Socket closed.'));
      }
    }
    _pending.clear();
    if (!_events.isClosed) await _events.close();
  }

  Future<Object?> _push({
    required String topic,
    required String event,
    required Map<String, Object?> payload,
    required String? joinRef,
  }) {
    final channel = _channel;
    if (channel == null) throw StateError('Socket is not open.');
    final ref = '${++_ref}';
    final completer = Completer<Object?>();
    _pending[ref] = completer;
    channel.sink.add(jsonEncode([joinRef, ref, topic, event, payload]));
    return completer.future.timeout(
      replyTimeout,
      onTimeout: () {
        _pending.remove(ref);
        throw TimeoutException('No reply to $event', replyTimeout);
      },
    );
  }

  void _onFrame(Object? raw) {
    final frame = jsonDecode(raw! as String) as List<Object?>;
    final ref = frame[1] as String?;
    final topic = frame[2]! as String;
    final event = frame[3]! as String;
    final payload = (frame[4] as Map?)?.cast<String, Object?>() ?? const {};
    if (event == 'phx_reply') {
      final pending = _pending.remove(ref);
      if (pending == null) return;
      final status = payload['status'];
      final response = payload['response'];
      if (status == 'ok') {
        pending.complete(response);
      } else {
        pending.completeError(PhoenixReplyException(event, response));
      }
      return;
    }
    if (event == 'phx_error' || event == 'phx_close') {
      _events.add(PhoenixEvent(topic: topic, event: event, payload: payload));
      return;
    }
    _events.add(PhoenixEvent(topic: topic, event: event, payload: payload));
  }

  void _onClosed() {
    // `close()` clears `_channel` first, so only a server-side drop errors.
    if (_channel != null && !_events.isClosed) {
      _events.addError(StateError('Socket closed by the server.'));
    }
  }

  /// `phoenix.js` appends `/websocket` and sends `vsn` plus the params.
  static Uri _socketUrl(Uri clientUrl, Map<String, String> params) {
    final path = clientUrl.path.endsWith('/websocket')
        ? clientUrl.path
        : '${clientUrl.path.replaceFirst(RegExp(r'/+$'), '')}/websocket';
    return clientUrl.replace(
      path: path,
      queryParameters: {
        ...clientUrl.queryParameters,
        ...params,
        'vsn': '2.0.0',
      },
    );
  }
}
