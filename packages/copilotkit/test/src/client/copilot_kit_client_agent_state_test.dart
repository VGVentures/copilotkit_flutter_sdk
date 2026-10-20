import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient agent state edits', () {
    late ClientHarness harness;
    late CopilotAgent agent;

    setUp(() {
      harness = ClientHarness();
      agent = harness.agent;
    });

    tearDown(() => harness.client.close());

    RunAgentInput sentInput() => harness.transport.sentInputs().last;

    void queueRun(List<BaseEvent> events) =>
        harness.runs.add(Stream.fromIterable(events));

    test('a run sends the state set before it', () async {
      queueRun(replyRun(agent.state.threadId));

      agent.setSharedState(const SharedState({'count': 3}));
      await harness.client.runAgent('default');

      expect(sentInput().state, {'count': 3});
    });

    test('a run sends the state patched before it', () async {
      queueRun(replyRun(agent.state.threadId));

      agent
        ..setSharedState(const SharedState({'count': 3}))
        ..patchSharedState(const [JsonPatchReplace(path: '/count', value: 4)]);
      await harness.client.runAgent('default');

      expect(sentInput().state, {'count': 4});
    });

    test('a run sends the messages set before it', () async {
      queueRun(replyRun(agent.state.threadId));

      agent
        ..addMessage(UserMessage(id: 'old', content: 'Old'))
        ..setMessages([UserMessage(id: 'new', content: 'New')]);
      await harness.client.runAgent('default');

      expect(sentInput().messages.map((message) => message.id), ['new']);
    });

    test('the state the runtime sends replaces a local edit', () async {
      final threadId = agent.state.threadId;
      queueRun([
        RunStartedEvent(threadId: threadId, runId: 'r1'),
        const StateSnapshotEvent(snapshot: {'count': 1}),
        RunFinishedEvent(threadId: threadId, runId: 'r1'),
      ]);

      agent.setSharedState(const SharedState({'count': 3}));
      await harness.client.runAgent('default');

      expect(sentInput().state, {'count': 3});
      expect(agent.state.sharedState, const SharedState({'count': 1}));
    });

    test('a state delta before any state applies to an empty object', () async {
      final threadId = agent.state.threadId;
      queueRun([
        RunStartedEvent(threadId: threadId, runId: 'r1'),
        const StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/count', 'value': 1},
          ],
        ),
        RunFinishedEvent(threadId: threadId, runId: 'r1'),
      ]);

      await harness.client.runAgent('default');

      expect(agent.state.sharedState, const SharedState({'count': 1}));
    });
  });
}
