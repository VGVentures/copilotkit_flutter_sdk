import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_transport.dart';
import 'package:http/http.dart' as http;

/// [AgentTransport] over a Copilot Runtime v2 using `ag_ui`'s SSE client.
///
/// Every run gets its own [http.Client], closed when the run ends or its
/// subscription is cancelled, so cancelling really closes the connection
/// (`ag_ui`'s own cancel only stops listening).
class AgUiTransport({
  required Uri runtimeUrl,
  http.Client Function()? httpClientFactory,
}) implements AgentTransport {
  /// Creates a transport for the runtime at [runtimeUrl].
  ///
  /// [httpClientFactory] creates the per-run client; defaults to
  /// [http.Client.new].
  this;

  final String _baseUrl = runtimeUrl.toString().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  final http.Client Function() _httpClientFactory =
      httpClientFactory ?? http.Client.new;
  final Set<http.Client> _activeClients = {};

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) {
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
                  return;
                }
                controller.addError(error, stackTrace);
              },
              onDone: () {
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
        release();
        unawaited(subscription?.cancel());
      },
    );
    return controller.stream;
  }

  /// Calls the runtime's stop route so the run also ends on the server.
  ///
  /// Throws an [http.ClientException] when the runtime rejects the request.
  @override
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  }) async {
    final url = Uri.parse(
      '$_baseUrl/agent/${Uri.encodeComponent(agentId)}'
      '/stop/${Uri.encodeComponent(threadId)}',
    );
    final httpClient = _httpClientFactory();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode({'runId': runId});
      final response = await http.Response.fromStream(
        await httpClient.send(request),
      );
      if (response.statusCode >= 400) {
        throw http.ClientException(
          'Stop failed with status ${response.statusCode}: ${response.body}',
          url,
        );
      }
    } finally {
      httpClient.close();
    }
  }

  @override
  Future<void> close() async {
    for (final client in _activeClients) {
      client.close();
    }
    _activeClients.clear();
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
