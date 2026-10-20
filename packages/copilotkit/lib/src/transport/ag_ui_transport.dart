import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:copilotkit/src/transport/models/stop_request.dart';
import 'package:http/http.dart' as http;

/// [AgentTransport] over a Copilot Runtime v2 using `ag_ui`'s SSE client.
///
/// Every run gets its own [http.Client], closed when the run ends or its
/// subscription is cancelled, so cancelling really closes the connection
/// (`ag_ui`'s own cancel only stops listening).
///
/// On the web the runtime must allow the app's origin with CORS; see the
/// README of the `copilotkit` package.
class AgUiTransport({
  required Uri runtimeUrl,
  http.Client Function()? httpClientFactory,
  Duration stopTimeout = const Duration(seconds: 10),
  void Function(Object error, StackTrace stackTrace)? onSkippedEvent,
}) implements AgentTransport {
  /// Creates a transport for the runtime at [runtimeUrl].
  ///
  /// [httpClientFactory] creates the per-run client; defaults to
  /// [http.Client.new].
  ///
  /// [stopTimeout] bounds the stop request, so a hung runtime can't hang
  /// `stop`.
  ///
  /// [onSkippedEvent] is called with each event the transport skipped because
  /// it couldn't be decoded, so apps can report it. Errors it throws are
  /// logged and don't end the run.
  this;

  final String _baseUrl = runtimeUrl.toString().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  final http.Client Function() _httpClientFactory =
      httpClientFactory ?? http.Client.new;
  final Duration _stopTimeout = stopTimeout;
  final void Function(Object error, StackTrace stackTrace)? _onSkippedEvent =
      onSkippedEvent;

  /// Ends each run in flight, see [close].
  final Set<void Function()> _runEnds = {};
  bool _closed = false;

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) {
    _ensureOpen();
    final httpClient = _httpClientFactory();
    final client = AgUiClient(
      config: AgUiClientConfig(baseUrl: _baseUrl, defaultHeaders: headers),
      httpClient: httpClient,
    );

    StreamSubscription<BaseEvent>? subscription;
    late final StreamController<BaseEvent> controller;
    // Ends the run once, however it ends: done, cancelled or closed. Closing
    // the client aborts the socket, which ends the inner stream. Don't wait
    // for ag_ui's cancel: it only completes once the body stream ends, and
    // stop must not block on the network.
    late final void Function() end;
    end = () {
      if (!_runEnds.remove(end)) return;
      httpClient.close();
      unawaited(_cancel(subscription));
      unawaited(controller.close());
    };
    _runEnds.add(end);
    controller = StreamController<BaseEvent>(
      onListen: () {
        // Closed before anyone listened: send nothing.
        if (_closed) return;
        subscription = client
            .runAgent(
              'agent/${Uri.encodeComponent(agentId)}/run',
              _simpleInput(input),
            )
            .listen(
              controller.add,
              onError: (Object error, StackTrace stackTrace) {
                // ag_ui reports each event it can't decode (unknown types,
                // missing fields, bad JSON) and keeps streaming. Skip them so
                // newer runtimes never break a run.
                if (_isDecodeError(error)) {
                  return _reportSkipped(error, stackTrace);
                }
                controller.addError(error, stackTrace);
              },
              onDone: end,
            );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: end,
    );
    return controller.stream;
  }

  /// Calls the runtime's stop route so the run also ends on the server.
  ///
  /// Throws an [http.ClientException] when the runtime rejects the request or
  /// doesn't answer within the stop timeout.
  @override
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  }) async {
    _ensureOpen();
    final url = Uri.parse(
      '$_baseUrl/agent/${Uri.encodeComponent(agentId)}'
      '/stop/${Uri.encodeComponent(threadId)}',
    );
    final httpClient = _httpClientFactory();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode(StopRequest(runId: runId));
      final response = await _send(httpClient, request).timeout(_stopTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Stop failed with status ${response.statusCode}: ${response.body}',
          url,
        );
      }
    } on TimeoutException {
      throw http.ClientException(
        'Stop timed out after ${_stopTimeout.inMilliseconds}ms.',
        url,
      );
    } finally {
      httpClient.close();
    }
  }

  /// Ends the runs in flight (their streams complete). The transport can't be
  /// used afterwards.
  @override
  Future<void> close() async {
    _closed = true;
    for (final end in [..._runEnds]) {
      end();
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('AgUiTransport is closed.');
  }

  /// Copies [input] into the [SimpleRunAgentInput] that `ag_ui`'s client
  /// sends to the runtime, field for field.
  SimpleRunAgentInput _simpleInput(RunAgentInput input) => SimpleRunAgentInput(
    threadId: input.threadId,
    runId: input.runId,
    parentRunId: input.parentRunId,
    state: input.state,
    messages: input.messages,
    tools: input.tools,
    context: input.context,
    forwardedProps: input.forwardedProps,
  );

  /// Whether [error] is `ag_ui` reporting an event it could not decode.
  bool _isDecodeError(Object error) =>
      error is DecodingError || error is AGUIValidationError;

  /// Logs an event skipped because it couldn't be decoded and reports it to
  /// `onSkippedEvent`, which must not break the run if it throws.
  void _reportSkipped(Object error, StackTrace stackTrace) {
    developer.log(
      'Skipped undecodable AG-UI event: $error',
      name: 'copilotkit',
    );
    try {
      _onSkippedEvent?.call(error, stackTrace);
    } on Object catch (callbackError, callbackStackTrace) {
      developer.log(
        'onSkippedEvent threw',
        name: 'copilotkit',
        level: 1000, // SEVERE
        error: callbackError,
        stackTrace: callbackStackTrace,
      );
    }
  }

  Future<http.Response> _send(http.Client client, http.Request request) async {
    final streamed = await client.send(request);
    return await http.Response.fromStream(streamed);
  }

  /// Cancels [subscription], ignoring errors from a connection that is
  /// already being torn down.
  Future<void> _cancel(StreamSubscription<BaseEvent>? subscription) async {
    try {
      await subscription?.cancel();
    } on Object {
      // Nothing to report.
    }
  }
}
