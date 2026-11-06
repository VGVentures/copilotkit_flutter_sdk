import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:copilotkit/src/transport/models/runtime_info.dart';
import 'package:copilotkit/src/transport/models/runtime_mode.dart';

/// [AgentTransport] that works out which kind of runtime it talks to, and
/// hands every call to the transport for that kind.
///
/// The first run or stop reads the runtime's `GET /info` with the headers of
/// that call. A runtime in [RuntimeMode.intelligence] mode gets the
/// Intelligence transport, any other gets the SSE transport.
///
/// A failed `/info` doesn't block the call: it goes to the SSE transport and
/// the error goes to `onInfoError`. Nothing is remembered about the failure,
/// so the next call asks again.
///
/// This class is mutable: it remembers the runtime's info once it has it.
class RuntimeSelectingTransport({
  required AgentTransport sse,
  required AgentTransport intelligence,
  void Function(Object error, StackTrace stackTrace)? onInfoError,
}) implements AgentTransport {
  /// Creates a transport that chooses between [sse] and [intelligence].
  ///
  /// [onInfoError] is called with each failure to read the runtime's info.
  this;

  final AgentTransport _sse = sse;
  final AgentTransport _intelligence = intelligence;
  final void Function(Object error, StackTrace stackTrace)? _onInfoError =
      onInfoError;

  RuntimeInfo? _info;
  Future<RuntimeInfo>? _pending;

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) {
    StreamSubscription<BaseEvent>? subscription;
    var cancelled = false;
    late final StreamController<BaseEvent> controller;
    controller = StreamController<BaseEvent>(
      onListen: () async {
        final transport = await _transportFor(headers);
        // Cancelled while the runtime was answering: start nothing.
        if (cancelled) return;
        try {
          subscription = transport
              .run(agentId: agentId, input: input, headers: headers)
              .listen(
                controller.add,
                onError: controller.addError,
                onDone: () => unawaited(controller.close()),
              );
          if (controller.isPaused) subscription?.pause();
        } on Object catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          unawaited(controller.close());
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        cancelled = true;
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  }) async {
    final transport = await _transportFor(headers);
    await transport.stop(
      agentId: agentId,
      threadId: threadId,
      runId: runId,
      headers: headers,
    );
  }

  /// Reads the runtime's info, once: later calls return what the first one
  /// read.
  ///
  /// Throws what the SSE transport's `info` throws.
  @override
  Future<RuntimeInfo> info({Map<String, String> headers = const {}}) async =>
      _info ?? await _fetch(headers);

  @override
  Future<void> close() async {
    await _sse.close();
    await _intelligence.close();
  }

  Future<RuntimeInfo> _fetch(Map<String, String> headers) => _pending ??= _sse
      .info(headers: headers)
      .then((info) => _info = info)
      .whenComplete(() => _pending = null);

  Future<AgentTransport> _transportFor(Map<String, String> headers) async {
    try {
      final info = _info ?? await _fetch(headers);
      return info.mode == RuntimeMode.intelligence ? _intelligence : _sse;
    } on Object catch (error, stackTrace) {
      _onInfoError?.call(error, stackTrace);
      return _sse;
    }
  }
}
