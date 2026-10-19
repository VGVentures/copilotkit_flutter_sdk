import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';

import 'mock_agent_transport.dart';
import 'test_copilot_kit_bloc.dart';

/// A client on a mocked transport for frontend tool tests.
///
/// Each run streams the next entry of [runs]; stops always succeed.
class ToolLoopHarness {
  /// Creates a harness with no queued runs.
  new() {
    transport
      ..stubRun(() => runs.removeAt(0))
      ..stubStop();
    when(transport.close).thenAnswer((_) async {});
  }

  /// The mocked transport behind [client].
  final MockAgentTransport transport = MockAgentTransport();

  /// Errors reported through the client's `onError`.
  final List<Object> errors = [];

  /// Event streams for the next runs, consumed in order.
  final List<Stream<BaseEvent>> runs = [];

  /// The client under test.
  late final TestCopilotKitBloc client = TestCopilotKitBloc(
    runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
    onError: (error, _) => errors.add(error),
    transport: transport,
  );

  /// The default agent of [client]; set by [open].
  late final CopilotAgentBloc agent;

  /// Opens the default agent.
  Future<void> open() async {
    agent = await client.openAgent('default');
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

/// A `confirmAction` human-in-the-loop tool with a required `action`.
HumanInTheLoopTool approvalTool({bool followUp = true}) {
  return HumanInTheLoopTool(
    name: 'confirmAction',
    description: 'Ask the user to confirm an action',
    parameters: Ack.object({'action': Ack.string()}),
    followUp: followUp,
  );
}

/// The events that start the `confirmAction` call [id] with [args], without
/// ending the run.
List<BaseEvent> approvalCall(
  String id, {
  String args = '{"action": "delete"}',
  String parentMessageId = 'a1',
}) {
  return [
    ToolCallStartEvent(
      toolCallId: id,
      toolCallName: 'confirmAction',
      parentMessageId: parentMessageId,
    ),
    ToolCallArgsEvent(toolCallId: id, delta: args),
    ToolCallEndEvent(toolCallId: id),
  ];
}

/// A run that calls `confirmAction` once per id in [ids], in one message.
List<BaseEvent> approvalRun(
  String threadId, {
  List<String> ids = const ['c1'],
  String args = '{"action": "delete"}',
}) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r1'),
    for (final id in ids) ...approvalCall(id, args: args),
    RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}
