import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/agent/reducer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

AgentState _replay(List<BaseEvent> events, [AgentState? initial]) =>
    events.fold(initial ?? const AgentState(), reduceAgentEvent);

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

  group('reduceAgentEvent state', () {
    test('StateSnapshot replaces the state', () {
      final snapshot = _replay(const [
        StateSnapshotEvent(snapshot: {'count': 1}),
        StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
      ]);

      expect(snapshot.sharedState, {'items': <Object?>[]});
    });

    test('StateDelta applies a JSON Patch to the state', () {
      final snapshot = _replay(const [
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

    test('StateDelta does not mutate the previous state', () {
      final before = reduceAgentEvent(
        const AgentState(),
        const StateSnapshotEvent(
          snapshot: {
            'items': ['a'],
          },
        ),
      );

      reduceAgentEvent(
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

    test('a StateDelta that does not apply leaves the snapshot unchanged', () {
      const snapshot = AgentState(sharedState: {'count': 1});

      expect(
        reduceAgentEvent(
          snapshot,
          const StateDeltaEvent(
            delta: [
              {'op': 'remove', 'path': '/missing'},
            ],
          ),
        ),
        same(snapshot),
      );
    });

    test('MessagesSnapshot replaces the messages', () {
      final old = UserMessage(id: 'u0', content: 'Old');
      final fresh = [
        UserMessage(id: 'u1', content: 'Hi'),
        const AssistantMessage(id: 'a1', content: 'Hello'),
      ];

      final snapshot = reduceAgentEvent(
        AgentState(messages: [old]),
        MessagesSnapshotEvent(messages: fresh),
      );

      expect(snapshot.messages, fresh);
    });
  });

  group('CopilotAgent state', () {
    test('state and stateStream follow snapshots and deltas', () async {
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
      agent.stateStream.listen(states.add);

      await agent.run();
      await pumpEventQueue();

      expect(agent.state, {'count': 2});
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

      expect(agent.state, {
        'todos': ['buy milk', 'walk dog'],
      });
    });
  });
}
