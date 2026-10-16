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
  /// it couldn't be decoded, so apps can report it.
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

  /// Clients of the runs in flight.
  final Set<http.Client> _activeClients = {};

  /// Ends each run in flight, see [close].
  final Set<void Function()> _runShutdowns = {};
  bool _closed = false;

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) {
    _ensureOpen();
    final httpClient = _httpClientFactory();
    _activeClients.add(httpClient);
    final client = AgUiClient(
      config: AgUiClientConfig(baseUrl: _baseUrl, defaultHeaders: headers),
      httpClient: httpClient,
    );

    void release() {
      if (_activeClients.remove(httpClient)) httpClient.close();
    }

    StreamSubscription<BaseEvent>? subscription;
    late final StreamController<BaseEvent> controller;
    late final void Function() shutdown;
    shutdown = () {
      _runShutdowns.remove(shutdown);
      release();
      unawaited(_cancel(subscription));
      unawaited(controller.close());
    };
    _runShutdowns.add(shutdown);
    controller = StreamController<BaseEvent>(
      onListen: () {
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
                  developer.log(
                    'Skipped undecodable AG-UI event: $error',
                    name: 'copilotkit',
                  );
                  _onSkippedEvent?.call(error, stackTrace);
                  return;
                }
                controller.addError(error, stackTrace);
              },
              onDone: () {
                _runShutdowns.remove(shutdown);
                release();
                unawaited(controller.close());
              },
            );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        // Closing the client aborts the socket, which ends the inner stream.
        // Don't wait for ag_ui's cancel: it only completes once the body
        // stream ends, and stop must not block on the network.
        _runShutdowns.remove(shutdown);
        release();
        unawaited(_cancel(subscription));
      },
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
        'Stop timed out after ${_stopTimeout.inSeconds}s.',
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
    for (final shutdown in [..._runShutdowns]) {
      shutdown();
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('AgUiTransport is closed.');
  }
}

Future<http.Response> _send(http.Client client, http.Request request) async {
  final streamed = await client.send(request);
  return await http.Response.fromStream(streamed);
}

Future<void> _cancel(StreamSubscription<BaseEvent>? subscription) async {
  try {
    await subscription?.cancel();
  } on Object {
    // The connection is already being torn down; nothing to report.
  }
}

SimpleRunAgentInput _simpleInput(RunAgentInput input) {
  return SimpleRunAgentInput(
    threadId: input.threadId,
    runId: input.runId,
    parentRunId: input.parentRunId,
    state: input.state,
    messages: input.messages,
    tools: input.tools,
    context: input.context,
    forwardedProps: input.forwardedProps,
  );
}

bool _isDecodeError(Object error) =>
    error is DecodingError || error is AGUIValidationError;
