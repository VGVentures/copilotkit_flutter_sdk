import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';

import 'client_x.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

/// A client on a mocked transport for frontend tool tests.
///
/// Each run streams the next entry of [runs]; stops always succeed.
class ToolLoopHarness {
  /// Creates a harness with no queued runs.
  new() {
    when(
      () => transport.run(
        agentId: any(named: 'agentId'),
        input: any(named: 'input'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) => runs.removeAt(0));
    when(
      () => transport.stop(
        agentId: any(named: 'agentId'),
        threadId: any(named: 'threadId'),
        runId: any(named: 'runId'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async {});
  }

  /// Registers the fallback `RunAgentInput` used by `any` matchers.
  static void registerFallbacks() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  }

  /// The mocked transport behind [client].
  final AgentTransport transport = _MockAgentTransport();

  /// Errors reported through the client's `onError`.
  final List<Object> errors = [];

  /// Event streams for the next runs, consumed in order.
  final List<Stream<BaseEvent>> runs = [];

  /// The client under test.
  late final CopilotKitClient client = CopilotKitClient(
    runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
    onError: (error, _) => errors.add(error),
    transport: transport,
  );

  /// The default agent of [client]; set by [open].
  late final CopilotAgent agent;

  /// Opens the default agent.
  Future<void> open() async {
    agent = await client.openAgent('default');
  }

  /// The inputs of every run sent so far, in order.
  List<RunAgentInput> sentInputs() {
    return verify(
      () => transport.run(
        agentId: any(named: 'agentId'),
        input: captureAny(named: 'input'),
        headers: any(named: 'headers'),
      ),
    ).captured.cast<RunAgentInput>();
  }
}

/// A `showWeather` tool with a required `city` and optional `days`.
FrontendTool weatherTool(FrontendToolHandler handler) {
  return FrontendTool(
    name: 'showWeather',
    description: 'Show the weather for a city',
    parameters: Ack.object({
      'city': Ack.string().describe('City name'),
      'days': Ack.integer().optional(),
    }),
    handler: handler,
  );
}

/// A run that calls the [name] tool with `{"city": "Lima"}` as call `c1`.
List<BaseEvent> toolCallRun(String threadId, {String name = 'showWeather'}) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r1'),
    ToolCallStartEvent(
      toolCallId: 'c1',
      toolCallName: name,
      parentMessageId: 'a1',
    ),
    const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Lima"}'),
    const ToolCallEndEvent(toolCallId: 'c1'),
    RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}

/// A run that replies `Sunny in Lima`.
List<BaseEvent> replyRun(String threadId) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r2'),
    const TextMessageStartEvent(messageId: 'a2'),
    const TextMessageContentEvent(messageId: 'a2', delta: 'Sunny in Lima'),
    RunFinishedEvent(threadId: threadId, runId: 'r2'),
  ];
}
