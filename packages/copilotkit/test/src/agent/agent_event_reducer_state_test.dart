import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:test/test.dart';

import '../../helpers/agent.dart';

void main() {
  group('$AgentEventReducer reduces state', () {
    test('StateSnapshot replaces the state', () {
      final result = reduce(const [
        ag_ui.StateSnapshotEvent(snapshot: {'count': 1}),
        ag_ui.StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
      ]);
      expect(result.states, [
        agentState.copyWith(sharedState: () => const SharedState({'count': 1})),
        agentState.copyWith(
          sharedState: () => const SharedState({'items': <Object?>[]}),
        ),
      ]);
    });

    test('StateSnapshot keeps an unmodifiable state', () {
      final result = reduce([
        ag_ui.StateSnapshotEvent(snapshot: Map.of(const {'count': 1})),
      ]);
      final state = result.states.single.sharedState!;

      expect(() => state.toJson()['count'] = 2, throwsUnsupportedError);
    });

    test('a null StateSnapshot clears the state', () {
      final result = reduce(
        const [ag_ui.StateSnapshotEvent(snapshot: null)],
        from: agentState.copyWith(
          sharedState: () => const SharedState({'count': 1}),
        ),
      );
      expect(result.states, [agentState]);
    });

    test('a StateSnapshot that is not an object leaves the state '
        'unchanged', () {
      final result = reduce(
        const [
          ag_ui.StateSnapshotEvent(snapshot: ['a']),
          ag_ui.StateSnapshotEvent(snapshot: 'text'),
        ],
        from: agentState.copyWith(
          sharedState: () => const SharedState({'count': 1}),
        ),
      );
      expect(result.states, const <CopilotAgentState>[]);
    });

    test('StateDelta keeps an unmodifiable state', () {
      final result = reduce(const [
        ag_ui.StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/count', 'value': 1},
          ],
        ),
      ]);
      final state = result.states.single.sharedState!;

      expect(() => state.toJson()['count'] = 2, throwsUnsupportedError);
    });

    test('StateDelta applies a JSON Patch to the state', () {
      final result = reduce(
        const [
          ag_ui.StateDeltaEvent(
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

    test('StateDelta applies to an empty object when there is no state', () {
      final result = reduce(const [
        ag_ui.StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/count', 'value': 1},
          ],
        ),
      ]);
      expect(result.states, [
        agentState.copyWith(sharedState: () => const SharedState({'count': 1})),
      ]);
    });

    final before = agentState.copyWith(
      sharedState: () => const SharedState({
        'items': ['a'],
      }),
    );

    test('StateDelta does not mutate the previous state', () {
      reduce(const [
        ag_ui.StateDeltaEvent(
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
          ag_ui.StateDeltaEvent(
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

    test('a StateDelta that replaces the state with a non-object is '
        'dropped', () {
      final result = reduce(
        const [
          ag_ui.StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '', 'value': 'text'},
            ],
          ),
        ],
        from: agentState.copyWith(
          sharedState: () => const SharedState({'count': 1}),
        ),
      );
      expect(result.states, const <CopilotAgentState>[]);
    });

    test('MessagesSnapshot replaces the messages', () {
      final result = reduce(
        [
          ag_ui.MessagesSnapshotEvent(
            messages: [
              ag_ui.UserMessage(id: 'u1', content: 'Hi'),
              const ag_ui.AssistantMessage(id: 'a1', content: 'Hello'),
            ],
          ),
        ],
        from: agentState.copyWith(
          messages: [const UserMessage(id: 'u0', content: 'Old')],
        ),
      );
      expect(result.states, [
        agentState.copyWith(
          messages: const [
            UserMessage(id: 'u1', content: 'Hi'),
            AssistantMessage(id: 'a1', content: 'Hello'),
          ],
        ),
      ]);
    });

    test('MessagesSnapshot keeps messages it cannot model', () {
      const reasoning = ag_ui.ReasoningMessage(id: 'r1', content: 'Hmm');
      final result = reduce([
        ag_ui.MessagesSnapshotEvent(messages: const [reasoning]),
      ]);
      expect(result.state.messages, [
        UnsupportedMessage(id: 'r1', data: reasoning.toJson()),
      ]);
    });
  });
}
