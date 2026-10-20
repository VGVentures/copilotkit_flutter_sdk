import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/client.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_agent_transport.dart';

/// An [AgentRunner], with its [RunStreamer] and [ToolCallRunner], on a
/// mocked transport, with its own tools, context and agent.
///
/// Each run streams the next entry of [runs]; stops always succeed.
class RunnerHarness {
  /// Creates a harness with no queued runs.
  ///
  /// [headers] and [properties] go to the runner. Errors are added to
  /// [errors] unless [onError] is given.
  new({
    HeadersBuilder? headers,
    Map<String, Object?>? properties,
    CopilotErrorHandler? onError,
  }) {
    transport
      ..stubRun(() => runs.removeAt(0))
      ..stubStop();
    when(transport.close).thenAnswer((_) async {});
    final report = onError ?? (error, _) => errors.add(error);
    streamer = RunStreamer(
      transport: transport,
      tools: tools,
      context: context,
      onError: report,
      headers: headers,
      properties: properties,
    );
    toolCalls = ToolCallRunner(tools: tools, onError: report);
    runner = AgentRunner(
      transport: transport,
      onError: report,
      streamer: streamer,
      toolCalls: toolCalls,
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

  /// Streams the runs of [runner].
  late final RunStreamer streamer;

  /// Runs the tool calls of [runner].
  late final ToolCallRunner toolCalls;

  /// The runner under test.
  late final AgentRunner runner;
}
