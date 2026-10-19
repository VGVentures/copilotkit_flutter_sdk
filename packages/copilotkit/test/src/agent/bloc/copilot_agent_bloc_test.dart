import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../helpers/agent.dart';
import '../../../helpers/fixtures.dart';

void main() {
  group(CopilotAgentBloc, () {
    final user = UserMessage(id: 'u1', content: 'Hi');

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'starts idle and empty with the given ids',
      build: buildAgent,
      verify: (agent) => expect(agent.state, agentState),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'generates a thread id when none is given',
      build: () => CopilotAgentBloc(agentId: 'default'),
      verify: (agent) =>
          expect(Uuid.isValidUUID(fromString: agent.state.threadId), isTrue),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentMessageAdded appends the message',
      build: buildAgent,
      act: (agent) => agent.add(AgentMessageAdded(user)),
      expect: () => [
        agentState.copyWith(messages: [user]),
      ],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentTurnStarted sets isRunning and clears the last error',
      build: buildAgent,
      seed: () => agentState.copyWith(error: () => 'boom'),
      act: (agent) => agent.add(const AgentTurnStarted()),
      expect: () => [agentState.copyWith(isRunning: true)],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentTurnEnded clears isRunning and keeps the rest',
      build: buildAgent,
      seed: () => agentState.copyWith(isRunning: true, error: () => 'boom'),
      act: (agent) => agent.add(const AgentTurnEnded()),
      expect: () => [agentState.copyWith(error: () => 'boom')],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentRunFailed records the error',
      build: buildAgent,
      seed: () => agentState.copyWith(isRunning: true),
      act: (agent) => agent.add(const AgentRunFailed('boom')),
      expect: () => [agentState.copyWith(isRunning: true, error: () => 'boom')],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentEventReceived applies the AG-UI event',
      build: buildAgent,
      act: (agent) => agent.add(
        const AgentEventReceived(TextMessageStartEvent(messageId: 'm1')),
      ),
      expect: () => [
        isA<CopilotAgentState>().having(
          (s) => s.messages.single.id,
          'message id',
          'm1',
        ),
      ],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'an event that changes nothing emits nothing',
      build: buildAgent,
      act: (agent) =>
          agent.add(const AgentEventReceived(StepStartedEvent(stepName: 's'))),
      expect: () => const <CopilotAgentState>[],
    );

    late Completer<void> settled;

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'AgentSettleRequested completes once earlier events are applied',
      setUp: () => settled = Completer<void>(),
      build: buildAgent,
      act: (agent) async {
        agent
          ..add(AgentMessageAdded(user))
          ..add(const AgentTurnStarted())
          ..add(AgentSettleRequested(settled));
        expect(agent.state.messages, isEmpty);

        await settled.future;

        expect(agent.state.messages, [user]);
        expect(agent.state.isRunning, isTrue);
      },
      expect: () => [
        agentState.copyWith(messages: [user]),
        agentState.copyWith(messages: [user], isRunning: true),
      ],
    );

    group(AgentStateSet, () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'replaces the shared state',
        build: buildAgent,
        seed: () => agentState.copyWith(sharedState: () => {'old': true}),
        act: (agent) => agent.add(const AgentStateSet({'count': 1})),
        expect: () => [
          agentState.copyWith(sharedState: () => {'count': 1}),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'clears the shared state with null',
        build: buildAgent,
        seed: () => agentState.copyWith(sharedState: () => {'old': true}),
        act: (agent) => agent.add(const AgentStateSet(null)),
        expect: () => [agentState],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'an equal state emits nothing',
        build: buildAgent,
        seed: () => agentState.copyWith(sharedState: () => {'count': 1}),
        act: (agent) => agent.add(const AgentStateSet({'count': 1})),
        expect: () => const <CopilotAgentState>[],
      );
    });

    group(AgentStatePatched, () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'applies the operations to the shared state',
        build: buildAgent,
        seed: () => agentState.copyWith(
          sharedState: () => {
            'count': 1,
            'items': ['a'],
          },
        ),
        act: (agent) => agent.add(
          const AgentStatePatched([
            {'op': 'replace', 'path': '/count', 'value': 2},
            {'op': 'add', 'path': '/items/-', 'value': 'b'},
          ]),
        ),
        expect: () => [
          agentState.copyWith(
            sharedState: () => {
              'count': 2,
              'items': ['a', 'b'],
            },
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'patches a missing state as an empty object',
        build: buildAgent,
        act: (agent) => agent.add(
          const AgentStatePatched([
            {'op': 'add', 'path': '/count', 'value': 1},
          ]),
        ),
        expect: () => [
          agentState.copyWith(sharedState: () => {'count': 1}),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'keeps the state and reports the error when an operation fails',
        build: buildAgent,
        seed: () => agentState.copyWith(sharedState: () => {'count': 1}),
        act: (agent) => agent.add(
          const AgentStatePatched([
            {'op': 'replace', 'path': '/count', 'value': 2},
            {'op': 'remove', 'path': '/missing'},
          ]),
        ),
        expect: () => const <CopilotAgentState>[],
        errors: () => [isA<FormatException>()],
        verify: (agent) => expect(agent.state.sharedState, {'count': 1}),
      );
    });

    group(AgentMessagesSet, () {
      const assistant = AssistantMessage(
        id: 'a1',
        toolCalls: [
          ToolCall(
            id: 'c1',
            function: FunctionCall(name: 'showWeather', arguments: '{}'),
          ),
        ],
      );
      const kept = ToolCallView(
        id: 'c1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
      );
      const dropped = ToolCallView(
        id: 'c2',
        name: 'showWeather',
        status: ToolCallStatus.complete,
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'replaces the messages',
        build: buildAgent,
        seed: () => agentState.copyWith(messages: [user]),
        act: (agent) => agent.add(const AgentMessagesSet([])),
        expect: () => [agentState],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'drops the tool calls no message refers to',
        build: buildAgent,
        seed: () => agentState.copyWith(
          messages: [user, assistant],
          toolCalls: [kept, dropped],
        ),
        act: (agent) => agent.add(const AgentMessagesSet([assistant])),
        expect: () => [
          agentState.copyWith(
            messages: const [assistant],
            toolCalls: const [kept],
          ),
        ],
      );
    });

    final fixture = loadFixture('text_stream');
    final deltas = [
      for (final event in fixture.events)
        if (event is TextMessageContentEvent) event.delta,
    ];

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'applies a recorded stream in order',
      build: buildAgent,
      act: (agent) => agent.receive(fixture.events),
      expect: () => [
        for (var i = 0; i <= deltas.length; i++)
          isA<CopilotAgentState>().having(
            (state) => state.messages.single.content,
            'text',
            deltas.take(i).join(),
          ),
      ],
    );
  });
}
