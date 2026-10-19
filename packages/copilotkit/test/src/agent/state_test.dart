import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/agent_reducer.dart';
import '../../helpers/client_x.dart';
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

    group('MessagesSnapshot rebuilds the tool calls', () {
      const call = ToolCall(
        id: 'c1',
        function: FunctionCall(name: 'search', arguments: '{"q": "dart"}'),
      );
      const assistant = AssistantMessage(id: 'a1', toolCalls: [call]);
      const result = ToolMessage(id: 't1', toolCallId: 'c1', content: 'found');

      test('creates views for calls that only the snapshot has', () async {
        final snapshot = await reduce(
          const AgentState(),
          MessagesSnapshotEvent(messages: [assistant]),
        );

        expect(snapshot.toolCalls, const [
          ToolCallView(
            id: 'c1',
            name: 'search',
            status: ToolCallStatus.executing,
            args: {'q': 'dart'},
          ),
        ]);
      });

      test('completes a call whose result arrives in the snapshot', () async {
        const executing = ToolCallView(
          id: 'c1',
          name: 'search',
          status: ToolCallStatus.executing,
          args: {'q': 'dart'},
        );

        final snapshot = await reduce(
          const AgentState(toolCalls: [executing]),
          MessagesSnapshotEvent(messages: [assistant, result]),
        );

        expect(snapshot.toolCalls.single.status, ToolCallStatus.complete);
        expect(snapshot.toolCalls.single.result, 'found');
        expect(snapshot.toolCalls.single.args, {'q': 'dart'});
      });

      test('drops views of calls the snapshot no longer has', () async {
        const stale = ToolCallView(
          id: 'gone',
          name: 'old',
          status: ToolCallStatus.executing,
        );

        final snapshot = await reduce(
          const AgentState(toolCalls: [stale]),
          MessagesSnapshotEvent(
            messages: [UserMessage(id: 'u1', content: 'Hi')],
          ),
        );

        expect(snapshot.toolCalls, isEmpty);
      });
    });
  });

  group('CopilotAgent state', () {
    test('sharedState follows snapshots and deltas', () async {
      final transport = _MockAgentTransport();
      final client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        transport: transport,
      );
      final agent = await client.openAgent('default');
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

      await client.runAgent(agent);
      await pumpEventQueue();

      expect(agent.state.sharedState, {'count': 2});
      expect(states, [
        {'count': 1},
        {'count': 2},
      ]);
    });

    test('state_snapshot_delta fixture applies the recorded patch', () async {
      final transport = _MockAgentTransport();
      final client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        transport: transport,
      );
      final agent = await client.openAgent('default');
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable(loadFixture('state_snapshot_delta').events),
      );

      await client.runAgent(agent);

      expect(agent.state.sharedState, {
        'todos': ['buy milk', 'walk dog'],
      });
    });
  });
}
