import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels/src/phoenix_frame.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockWebSocketChannel extends Mock implements WebSocketChannel;

class MockWebSocketSink extends Mock implements WebSocketSink;

/// A socket the tests drive by hand: they decide whether the handshake
/// succeeds, what the server sends and when it closes.
class FakeSocket() {
  this {
    when(() => channel.ready).thenAnswer((_) => _ready.future);
    when(() => channel.stream).thenAnswer((_) => _incoming.stream);
    when(() => channel.sink).thenReturn(sink);
    when(() => channel.closeCode).thenAnswer((_) => closeCode);
    when(() => channel.closeReason).thenAnswer((_) => closeReason);
    when(() => sink.add(any<Object?>())).thenAnswer((invocation) {
      final frame = PhoenixFrame.decode(
        invocation.positionalArguments.first! as String,
      );
      sentFrames.add(frame);
      onFrame?.call(frame);
    });
    when(sink.close).thenAnswer((_) async {
      closedByClient = true;
      unawaited(_incoming.close());
    });
    _ready.complete();
  }

  final MockWebSocketChannel channel = MockWebSocketChannel();
  final MockWebSocketSink sink = MockWebSocketSink();

  /// What the client sent, in order.
  final List<PhoenixFrame> sentFrames = [];

  /// Called with each frame the client sends, to let a test answer it.
  void Function(PhoenixFrame frame)? onFrame;

  /// The URL the client connected to.
  Uri? connectedTo;

  /// The close code the socket reports once the server closed it.
  int? closeCode;

  /// The close reason the socket reports once the server closed it.
  String? closeReason;

  /// Whether the client closed the socket.
  bool closedByClient = false;

  Completer<void> _ready = Completer<void>();
  final StreamController<Object?> _incoming = StreamController<Object?>();

  /// Lets what was scheduled so far run.
  Future<void> settle([Duration duration = Duration.zero]) =>
      Future<void>.delayed(duration);

  /// Waits until [condition] holds, polling, and fails after [timeout].
  Future<void> until(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!condition()) {
      if (stopwatch.elapsed > timeout) {
        throw TimeoutException('The condition never held.', timeout);
      }
      await settle(const Duration(milliseconds: 5));
    }
  }

  /// The `connect` the client is given.
  WebSocketChannel connect(Uri uri) {
    connectedTo = uri;
    return channel;
  }

  /// Makes the handshake fail with [error]. Call it before the client opens.
  void failHandshake(Object error) {
    _ready = Completer<void>()..completeError(error);
  }

  /// The server sends [frame].
  void serverSends(PhoenixFrame frame) {
    if (_incoming.isClosed) return;
    _incoming.add(frame.encode());
  }

  /// The server sends [data] as it is, text or binary.
  void serverSendsRaw(Object? data) => _incoming.add(data);

  /// The socket reports [error] on its stream.
  void streamFails(Object error) => _incoming.addError(error);

  /// The server closes the socket.
  Future<void> serverCloses({int? code, String? reason}) {
    closeCode = code;
    closeReason = reason;
    return _incoming.close();
  }

  /// A reply to [request] with [status] and [response].
  PhoenixFrame replyTo(
    PhoenixFrame request, {
    String status = 'ok',
    Object? response = const <String, Object?>{},
  }) => PhoenixFrame(
    joinRef: request.joinRef,
    ref: request.ref,
    topic: request.topic,
    event: 'phx_reply',
    payload: {'status': status, 'response': response},
  );
}
