import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_agent_transport.dart';

/// An [AgentRunner] on a mocked transport, with its own tools, context and
/// agent.
///
/// Each run streams the next entry of [runs]; stops always succeed.
class RunnerHarness {
  /// Creates a harness with no queued runs.
  ///
  /// [headers] and [properties] go to the runner. Errors are added to
  /// [errors] unless [onError] is given.
  new({
    HeadersBuilder? headers,
    JsonEncodable? properties,
    CopilotErrorHandler? onError,
  }) {
    transport
      ..stubRun(() => runs.removeAt(0))
      ..stubStop();
    when(transport.close).thenAnswer((_) async {});
    runner = AgentRunner(
      transport: transport,
      tools: tools,
      context: context,
      onError: onError ?? (error, _) => errors.add(error),
      headers: headers,
      properties: properties,
    );
  }

  /// The mocked transport behind [runner].
  final MockAgentTransport transport = MockAgentTransport();

  /// The tools sent with every run.
  final ToolRegistry tools = ToolRegistry();

  /// The context sent with every run.
  final AgentContextStore context = AgentContextStore();

  /// Errors reported to the runner's error handler.
  final List<Object> errors = [];

  /// Event streams for the next runs, consumed in order.
  final List<Stream<BaseEvent>> runs = [];

  /// The agent the tests run.
  final CopilotAgent agent = CopilotAgent(agentId: 'default');

  /// The runner under test.
  late final AgentRunner runner;
}
