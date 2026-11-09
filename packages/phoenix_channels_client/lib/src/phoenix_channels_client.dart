import 'dart:async';

import 'package:phoenix_channels_client/src/phoenix_closed_exception.dart';
import 'package:phoenix_channels_client/src/phoenix_endpoint.dart';
import 'package:phoenix_channels_client/src/phoenix_event.dart';
import 'package:phoenix_channels_client/src/phoenix_frame.dart';
import 'package:phoenix_channels_client/src/phoenix_reply_exception.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A client of the Phoenix channels protocol, version 2, for one socket and
/// one topic.
///
/// Listen to [events], call [open], then [join] the topic. [push] sends an
/// event on the joined topic and waits for its reply. A heartbeat keeps the
/// connection honest: when the server doesn't answer one within the reply
/// timeout, the connection is dropped and reported like a closed socket.
///
/// The client never reconnects. When the connection ends, for any reason,
/// [events] reports it with an error and the client can't be used again.
/// Create a new one, with new credentials if the server needs them.
///
/// This class is mutable: it tracks the socket and the pushes waiting for a
/// reply. Call [close] when done.
class PhoenixChannelsClient({
  /// The URL of the socket, without the `/websocket` transport path.
  required Uri clientUrl,

  /// The query parameters sent with the handshake, such as a join token.
  Map<String, String> params = const {},

  /// The time between heartbeats.
  final Duration heartbeatInterval = const Duration(seconds: 30),

  /// How long to wait for the reply to a join, a push or a heartbeat.
  final Duration replyTimeout = const Duration(seconds: 10),

  /// Opens the WebSocket. Defaults to [WebSocketChannel.connect]; tests pass a
  /// fake.
  WebSocketChannel Function(Uri uri)? connect,
}) {
  /// Creates a client for the socket at [clientUrl]. It connects only when
  /// [open] is called.
  this;

  final Uri _socketUrl = PhoenixEndpoint(
    url: clientUrl,
    params: params,
  ).socketUrl;
  final WebSocketChannel Function(Uri uri) _connect =
      connect ?? WebSocketChannel.connect;
  final StreamController<PhoenixEvent> _events =
      StreamController<PhoenixEvent>.broadcast();
  final Map<String, Completer<Object?>> _pending = {};
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  int _lastRef = 0;
  String? _joinRef;
  bool _opening = false;
  bool _closed = false;
  bool _failed = false;

  /// What the server pushes, other than replies, on every topic.
  ///
  /// It is a broadcast stream: listen before [open], or early frames are
  /// lost. When the connection ends other than through [close], it emits a
  /// [PhoenixClosedException] (or the error the socket or the heartbeat
  /// timeout reported) as an error. [close] ends the stream without an error.
  Stream<PhoenixEvent> get events => _events.stream;

  bool get _ended => _closed || _failed;

  /// Opens the socket and starts the heartbeat.
  ///
  /// Throws when the handshake fails, for example when the server refuses the
  /// parameters, and a [StateError] when the client is open or closed.
  Future<void> open() async {
    if (_closed) {
      throw StateError('PhoenixChannelsClient is closed.');
    }
    if (_channel != null || _opening) {
      throw StateError('PhoenixChannelsClient is already open.');
    }
    _opening = true;
    try {
      final channel = _connect(_socketUrl);
      await channel.ready;
      if (_closed) {
        // close() ran during the handshake: don't keep the connection.
        await channel.sink.close();
        throw const PhoenixClosedException();
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: _fail,
        onDone: _onDone,
      );
      _heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_beat()));
    } finally {
      _opening = false;
    }
  }

  /// Joins [topic] with [params] and returns the `response` of the reply.
  ///
  /// Later calls to [push] belong to this join. Throws a
  /// [PhoenixReplyException] when the server answers with an error, a
  /// [TimeoutException] when it doesn't answer, and a
  /// [PhoenixClosedException] when the connection ended first.
  Future<Object?> join(String topic, Map<String, Object?> params) async {
    final joinRef = '${_lastRef + 1}';
    final response = await _push(
      topic: topic,
      event: 'phx_join',
      payload: params,
      joinRef: joinRef,
    );
    // Only a join the server accepted changes the ref later pushes send.
    _joinRef = joinRef;
    return response;
  }

  /// Pushes [event] on [topic] and returns the `response` of the reply.
  ///
  /// Throws like [join].
  Future<Object?> push(
    String topic,
    String event,
    Map<String, Object?> payload,
  ) => _push(topic: topic, event: event, payload: payload, joinRef: _joinRef);

  /// Closes the socket, fails the pushes still waiting with a
  /// [PhoenixClosedException] and ends [events]. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    _failPending(const PhoenixClosedException());
    try {
      await _subscription?.cancel();
      await _channel?.sink.close();
    } finally {
      await _events.close();
    }
  }

  Future<Object?> _push({
    required String topic,
    required String event,
    required Map<String, Object?> payload,
    required String? joinRef,
  }) async {
    if (_ended) throw const PhoenixClosedException();
    final channel = _channel;
    if (channel == null) throw StateError('PhoenixChannelsClient is not open.');
    final ref = '${++_lastRef}';
    final reply = Completer<Object?>();
    _pending[ref] = reply;
    channel.sink.add(
      PhoenixFrame(
        joinRef: joinRef,
        ref: ref,
        topic: topic,
        event: event,
        payload: payload,
      ).encode(),
    );
    return await reply.future.timeout(
      replyTimeout,
      onTimeout: () {
        _pending.remove(ref);
        throw TimeoutException('No reply to $event.', replyTimeout);
      },
    );
  }

  /// Sends a heartbeat. No reply in time means the connection is half open, so
  /// it is reported and dropped.
  Future<void> _beat() async {
    try {
      await _push(
        topic: 'phoenix',
        event: 'heartbeat',
        payload: const {},
        joinRef: null,
      );
    } on TimeoutException catch (error) {
      _fail(error);
      await _channel?.sink.close();
    } on Object {
      // The connection ended while the heartbeat was waiting. That has been
      // reported already.
    }
  }

  void _onData(Object? data) {
    if (_ended || data is! String) return;
    final PhoenixFrame frame;
    try {
      frame = PhoenixFrame.decode(data);
    } on FormatException catch (error) {
      _events.addError(error);
      return;
    }
    if (!frame.isReply) {
      _events.add(
        PhoenixEvent(
          topic: frame.topic,
          event: frame.event,
          payload: frame.payload,
        ),
      );
      return;
    }
    final reply = _pending.remove(frame.ref);
    if (reply == null) return;
    if (frame.status == 'ok') {
      reply.complete(frame.response);
    } else {
      reply.completeError(
        PhoenixReplyException(
          status: frame.status ?? 'unknown',
          response: frame.response,
        ),
      );
    }
  }

  void _onDone() => _fail(
    PhoenixClosedException(
      code: _channel?.closeCode,
      reason: _channel?.closeReason,
    ),
  );

  /// Ends the connection with [error]: reports it once, stops the heartbeat
  /// and fails the pushes still waiting. Does nothing when it already ended.
  void _fail(Object error) {
    if (_ended) return;
    _failed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    _events.addError(error);
    _failPending(error);
  }

  void _failPending(Object error) {
    for (final reply in _pending.values) {
      reply.completeError(error);
    }
    _pending.clear();
  }
}
