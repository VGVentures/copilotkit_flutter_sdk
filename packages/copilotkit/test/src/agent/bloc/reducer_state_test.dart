import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';

void main() {
  group('$CopilotAgentBloc reduces state', () {
    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateSnapshot replaces the state',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        StateSnapshotEvent(snapshot: {'count': 1}),
        StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
      ]),
      expect: () => [
        agentState.copyWith(sharedState: () => {'count': 1}),
        agentState.copyWith(sharedState: () => {'items': <Object?>[]}),
      ],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateDelta applies a JSON Patch to the state',
      build: buildAgent,
      seed: () => agentState.copyWith(
        sharedState: () => {
          'count': 1,
          'items': ['a'],
        },
      ),
      act: (agent) => agent.receive(const [
        StateDeltaEvent(
          delta: [
            {'op': 'replace', 'path': '/count', 'value': 2},
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ],
        ),
      ]),
      expect: () => [
        agentState.copyWith(
          sharedState: () => {
            'count': 2,
            'items': ['a', 'b'],
          },
        ),
      ],
    );

    final before = agentState.copyWith(
      sharedState: () => {
        'items': ['a'],
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateDelta does not mutate the previous state',
      build: buildAgent,
      seed: () => before,
      act: (agent) => agent.receive(const [
        StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ],
        ),
      ]),
      verify: (_) => expect(before.sharedState, {
        'items': ['a'],
      }),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'a StateDelta that does not apply leaves the state unchanged',
      build: buildAgent,
      seed: () => agentState.copyWith(sharedState: () => {'count': 1}),
      act: (agent) => agent.receive(const [
        StateDeltaEvent(
          delta: [
            {'op': 'remove', 'path': '/missing'},
          ],
        ),
      ]),
      expect: () => const <CopilotAgentState>[],
    );

    final fresh = [
      UserMessage(id: 'u1', content: 'Hi'),
      const AssistantMessage(id: 'a1', content: 'Hello'),
    ];

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'MessagesSnapshot replaces the messages',
      build: buildAgent,
      seed: () => agentState.copyWith(
        messages: [UserMessage(id: 'u0', content: 'Old')],
      ),
      act: (agent) => agent.receive([MessagesSnapshotEvent(messages: fresh)]),
      expect: () => [agentState.copyWith(messages: fresh)],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateDelta applies to an empty object when there is no state yet',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/count', 'value': 1},
          ],
        ),
      ]),
      expect: () => [
        agentState.copyWith(sharedState: () => {'count': 1}),
      ],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateSnapshot overwrites a local edit',
      build: buildAgent,
      act: (agent) => agent
        ..add(const AgentStateSet({'count': 5}))
        ..receive(const [
          StateSnapshotEvent(snapshot: {'count': 1}),
        ]),
      expect: () => [
        agentState.copyWith(sharedState: () => {'count': 5}),
        agentState.copyWith(sharedState: () => {'count': 1}),
      ],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'StateDelta patches a local edit',
      build: buildAgent,
      act: (agent) => agent
        ..add(const AgentStateSet({'count': 5}))
        ..receive(const [
          StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '/count', 'value': 6},
            ],
          ),
        ]),
      expect: () => [
        agentState.copyWith(sharedState: () => {'count': 5}),
        agentState.copyWith(sharedState: () => {'count': 6}),
      ],
    );
  });
}
