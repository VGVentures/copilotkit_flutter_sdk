import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:test/test.dart';

import '../../helpers/agent.dart';

void main() {
  group('$AgentEventReducer reduces state', () {
    test('StateSnapshot replaces the state', () {
      final result = reduce(const [
        StateSnapshotEvent(snapshot: {'count': 1}),
        StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
      ]);
      expect(result.states, [
        agentState.copyWith(sharedState: () => const SharedState({'count': 1})),
        agentState.copyWith(
          sharedState: () => const SharedState({'items': <Object?>[]}),
        ),
      ]);
    });

    test('StateDelta applies a JSON Patch to the state', () {
      final result = reduce(
        const [
          StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '/count', 'value': 2},
              {'op': 'add', 'path': '/items/-', 'value': 'b'},
            ],
          ),
        ],
        from: agentState.copyWith(
          sharedState: () => const SharedState({
            'count': 1,
            'items': ['a'],
          }),
        ),
      );
      expect(result.states, [
        agentState.copyWith(
          sharedState: () => const SharedState({
            'count': 2,
            'items': ['a', 'b'],
          }),
        ),
      ]);
    });

    final before = agentState.copyWith(
      sharedState: () => const SharedState({
        'items': ['a'],
      }),
    );

    test('StateDelta does not mutate the previous state', () {
      reduce(const [
        StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ],
        ),
      ], from: before);
      expect(
        before.sharedState,
        const SharedState({
          'items': ['a'],
        }),
      );
    });

    test('a StateDelta that does not apply leaves the state unchanged', () {
      final result = reduce(
        const [
          StateDeltaEvent(
            delta: [
              {'op': 'remove', 'path': '/missing'},
            ],
          ),
        ],
        from: agentState.copyWith(
          sharedState: () => const SharedState({'count': 1}),
        ),
      );
      expect(result.states, const <CopilotAgentState>[]);
    });

    final fresh = [
      UserMessage(id: 'u1', content: 'Hi'),
      const AssistantMessage(id: 'a1', content: 'Hello'),
    ];

    test('MessagesSnapshot replaces the messages', () {
      final result = reduce(
        [MessagesSnapshotEvent(messages: fresh)],
        from: agentState.copyWith(
          messages: [UserMessage(id: 'u0', content: 'Old')],
        ),
      );
      expect(result.states, [agentState.copyWith(messages: fresh)]);
    });
  });
}
