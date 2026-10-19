import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('agent state edits', () {
    late ToolLoopHarness harness;
    late CopilotAgentBloc agent;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      agent = harness.agent;
      harness.runs.add(Stream.fromIterable(replyRun(agent.state.threadId)));
    });

    RunAgentInput sentInput() => harness.transport.sentInputs().last;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a run sends the state set just before it, in the same tick',
      build: () => harness.client,
      act: (_) async {
        agent.add(const AgentStateSet({'count': 3}));
        await harness.client.runAgent(agent);
      },
      verify: (_) => expect(sentInput().state, {'count': 3}),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a run sends the state patched just before it',
      build: () => harness.client,
      act: (_) async {
        agent
          ..add(const AgentStateSet({'count': 3}))
          ..add(
            const AgentStatePatched([
              {'op': 'replace', 'path': '/count', 'value': 4},
            ]),
          );
        await harness.client.runAgent(agent);
      },
      verify: (_) => expect(sentInput().state, {'count': 4}),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a run sends the messages set just before it',
      build: () => harness.client,
      act: (_) async {
        agent
          ..add(AgentMessageAdded(UserMessage(id: 'old', content: 'Old')))
          ..add(AgentMessagesSet([UserMessage(id: 'new', content: 'New')]));
        await harness.client.runAgent(agent);
      },
      verify: (_) =>
          expect(sentInput().messages.map((message) => message.id), ['new']),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'the state the runtime sends replaces a local edit',
      setUp: () {
        harness.runs
          ..clear()
          ..add(
            Stream.fromIterable([
              RunStartedEvent(threadId: agent.state.threadId, runId: 'r1'),
              const StateSnapshotEvent(snapshot: {'count': 1}),
              RunFinishedEvent(threadId: agent.state.threadId, runId: 'r1'),
            ]),
          );
      },
      build: () => harness.client,
      act: (_) async {
        agent.add(const AgentStateSet({'count': 3}));
        await harness.client.runAgent(agent);
      },
      verify: (_) {
        expect(sentInput().state, {'count': 3});
        expect(agent.state.sharedState, {'count': 1});
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a state delta before any state applies to an empty object',
      setUp: () {
        harness.runs
          ..clear()
          ..add(
            Stream.fromIterable([
              RunStartedEvent(threadId: agent.state.threadId, runId: 'r1'),
              const StateDeltaEvent(
                delta: [
                  {'op': 'add', 'path': '/count', 'value': 1},
                ],
              ),
              RunFinishedEvent(threadId: agent.state.threadId, runId: 'r1'),
            ]),
          );
      },
      build: () => harness.client,
      act: (_) => harness.client.runAgent(agent),
      verify: (_) => expect(agent.state.sharedState, {'count': 1}),
    );
  });
}
