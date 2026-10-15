import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/agent_reducer.dart';
import '../../helpers/fixtures.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  });

  group('CopilotAgent reduces state', () {
    test('StateSnapshot replaces the state', () async {
      final snapshot = await replay(const [
        StateSnapshotEvent(snapshot: {'count': 1}),
        StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
      ]);

      expect(snapshot.sharedState, {'items': <Object?>[]});
    });

    test('StateDelta applies a JSON Patch to the state', () async {
      final snapshot = await replay(const [
        StateSnapshotEvent(
          snapshot: {
            'count': 1,
            'items': ['a'],
          },
        ),
        StateDeltaEvent(
          delta: [
            {'op': 'replace', 'path': '/count', 'value': 2},
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ],
        ),
      ]);

      expect(snapshot.sharedState, {
        'count': 2,
        'items': ['a', 'b'],
      });
    });

    test('StateDelta does not mutate the previous state', () async {
      final before = await reduce(
        const AgentState(),
        const StateSnapshotEvent(
          snapshot: {
            'items': ['a'],
          },
        ),
      );

      await reduce(
        before,
        const StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ],
        ),
      );

      expect(before.sharedState, {
        'items': ['a'],
      });
    });

    test(
      'a StateDelta that does not apply leaves the snapshot unchanged',
      () async {
        const snapshot = AgentState(sharedState: {'count': 1});

        expect(
          await reduce(
            snapshot,
            const StateDeltaEvent(
              delta: [
                {'op': 'remove', 'path': '/missing'},
              ],
            ),
          ),
          same(snapshot),
        );
      },
    );

    test('MessagesSnapshot replaces the messages', () async {
      final old = UserMessage(id: 'u0', content: 'Old');
      final fresh = [
        UserMessage(id: 'u1', content: 'Hi'),
        const AssistantMessage(id: 'a1', content: 'Hello'),
      ];

      final snapshot = await reduce(
        AgentState(messages: [old]),
        MessagesSnapshotEvent(messages: fresh),
      );

      expect(snapshot.messages, fresh);
    });
  });

  group('CopilotAgent state', () {
    test('sharedState follows snapshots and deltas', () async {
      final transport = _MockAgentTransport();
      final agent = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        transport: transport,
      ).agent('default');
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          RunStartedEvent(threadId: agent.threadId, runId: 'r'),
          const StateSnapshotEvent(snapshot: {'count': 1}),
          const TextMessageStartEvent(messageId: 'm1'),
          const StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '/count', 'value': 2},
            ],
          ),
          RunFinishedEvent(threadId: agent.threadId, runId: 'r'),
        ]),
      );
      final states = <Object?>[];
      agent.stream
          .map((state) => state.sharedState)
          .where((shared) => shared != null)
          .distinct()
          .listen(states.add);

      await agent.run();
      await pumpEventQueue();

      expect(agent.state.sharedState, {'count': 2});
      expect(states, [
        {'count': 1},
        {'count': 2},
      ]);
    });

    test('state_snapshot_delta fixture applies the recorded patch', () async {
      final transport = _MockAgentTransport();
      final agent = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        transport: transport,
      ).agent('default');
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable(loadFixture('state_snapshot_delta').events),
      );

      await agent.run();

      expect(agent.state.sharedState, {
        'todos': ['buy milk', 'walk dog'],
      });
    });
  });
}
