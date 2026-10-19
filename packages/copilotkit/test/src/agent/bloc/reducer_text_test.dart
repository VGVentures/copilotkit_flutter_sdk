import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';
import '../../../helpers/fixtures.dart';

void main() {
  group('$CopilotAgentBloc reduces', () {
    group('lifecycle', () {
      final user = UserMessage(id: 'u1', content: 'Hi');

      // The client owns isRunning for the whole turn (runs plus tool
      // handlers), so lifecycle events never toggle it.
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'RunStarted clears the previous error, not isRunning',
        build: buildAgent,
        seed: () => agentState.copyWith(isRunning: true, error: () => 'boom'),
        act: (agent) =>
            agent.receive([RunStartedEvent(threadId: 't', runId: 'r')]),
        expect: () => [agentState.copyWith(isRunning: true)],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'RunFinished leaves isRunning to the client',
        build: buildAgent,
        seed: () => agentState.copyWith(isRunning: true),
        act: (agent) =>
            agent.receive(const [RunFinishedEvent(threadId: 't', runId: 'r')]),
        expect: () => const <CopilotAgentState>[],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'RunError keeps the error and leaves isRunning',
        build: buildAgent,
        seed: () => agentState.copyWith(isRunning: true),
        act: (agent) => agent.receive(const [
          RunErrorEvent(message: 'Bad key', code: 'AUTH'),
        ]),
        expect: () => [
          agentState.copyWith(
            isRunning: true,
            error: () => const RunErrorEvent(message: 'Bad key', code: 'AUTH'),
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'steps leave the state unchanged',
        build: buildAgent,
        seed: () => agentState.copyWith(isRunning: true),
        act: (agent) => agent.receive(const [
          StepStartedEvent(stepName: 's'),
          StepFinishedEvent(stepName: 's'),
        ]),
        expect: () => const <CopilotAgentState>[],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'keeps messages and state across the run',
        build: buildAgent,
        seed: () => agentState.copyWith(
          messages: [user],
          sharedState: () => const {'a': 1},
          error: () => 'boom',
        ),
        act: (agent) => agent.receive([
          RunStartedEvent(threadId: 't', runId: 'r'),
          const RunFinishedEvent(threadId: 't', runId: 'r'),
        ]),
        expect: () => [
          agentState.copyWith(
            messages: [user],
            sharedState: () => const {'a': 1},
          ),
        ],
      );
    });

    group('text messages', () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Start appends an empty message with the given role',
        build: buildAgent,
        act: (agent) =>
            agent.receive(const [TextMessageStartEvent(messageId: 'm1')]),
        expect: () => [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single,
            'message',
            isA<AssistantMessage>()
                .having((m) => m.id, 'id', 'm1')
                .having((m) => m.content, 'content', ''),
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content grows the message text on every delta',
        build: buildAgent,
        act: (agent) => agent.receive([
          const TextMessageStartEvent(messageId: 'm1'),
          for (final delta in ['Hel', 'lo', ' there'])
            TextMessageContentEvent(messageId: 'm1', delta: delta),
        ]),
        skip: 1,
        expect: () => [
          for (final text in ['Hel', 'Hello', 'Hello there'])
            isA<CopilotAgentState>().having(
              (state) => state.messages.single.content,
              'text',
              text,
            ),
        ],
      );

      final started = agentState.copyWith(
        messages: [const AssistantMessage(id: 'm1', content: '')],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content does not mutate earlier states',
        build: buildAgent,
        seed: () => started,
        act: (agent) => agent.receive(const [
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]),
        verify: (_) => expect(started.messages.single.content, ''),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content appends to the right message by id',
        build: buildAgent,
        seed: () => agentState.copyWith(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
        act: (agent) => agent.receive(const [
          TextMessageStartEvent(messageId: 'm1'),
          TextMessageContentEvent(messageId: 'm1', delta: 'First'),
          TextMessageStartEvent(messageId: 'm2'),
          TextMessageContentEvent(messageId: 'm2', delta: 'Second'),
          TextMessageContentEvent(messageId: 'm1', delta: '!'),
        ]),
        verify: (agent) => expect(agent.state.messages.map((m) => m.content), [
          'Hi',
          'First!',
          'Second',
        ]),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content without a Start creates an assistant message',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]),
        expect: () => [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single,
            'message',
            isA<AssistantMessage>().having((m) => m.content, 'content', 'Hi'),
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'End leaves the state unchanged',
        build: buildAgent,
        seed: () => started,
        act: (agent) =>
            agent.receive(const [TextMessageEndEvent(messageId: 'm1')]),
        expect: () => const <CopilotAgentState>[],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Start keeps non-assistant roles',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          TextMessageStartEvent(messageId: 'u', role: TextMessageRole.user),
          TextMessageContentEvent(messageId: 'u', delta: 'Hi'),
          TextMessageStartEvent(messageId: 's', role: TextMessageRole.system),
          TextMessageContentEvent(messageId: 's', delta: 'Be nice'),
          TextMessageStartEvent(
            messageId: 'd',
            role: TextMessageRole.developer,
          ),
          TextMessageContentEvent(messageId: 'd', delta: 'Debug'),
        ]),
        verify: (agent) => expect(agent.state.messages, [
          isA<UserMessage>().having((m) => m.content, 'content', 'Hi'),
          isA<SystemMessage>().having((m) => m.content, 'content', 'Be nice'),
          isA<DeveloperMessage>().having((m) => m.content, 'content', 'Debug'),
        ]),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content aimed at a non-text message leaves it unchanged',
        build: buildAgent,
        seed: () => agentState.copyWith(
          messages: const [
            ToolMessage(id: 'x', content: 'result', toolCallId: 'c'),
          ],
        ),
        act: (agent) => agent.receive(const [
          TextMessageContentEvent(messageId: 'x', delta: 'Hi'),
        ]),
        verify: (agent) => expect(
          agent.state.messages.single,
          isA<ToolMessage>().having((m) => m.content, 'content', 'result'),
        ),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'Content keeps the name of the message',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          TextMessageStartEvent(messageId: 'm1', name: 'helper'),
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]),
        verify: (agent) => expect(agent.state.messages.single.name, 'helper'),
      );
    });

    group('text message chunks', () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'first chunk creates the message, later chunks grow it',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'Hel'),
          TextMessageChunkEvent(delta: 'lo'),
          TextMessageChunkEvent(messageId: 'm1', delta: '!'),
        ]),
        verify: (agent) => expect(
          agent.state.messages.single,
          isA<AssistantMessage>()
              .having((m) => m.id, 'id', 'm1')
              .having((m) => m.content, 'content', 'Hello!'),
        ),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk with a new id starts a new message',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'One'),
          TextMessageChunkEvent(
            messageId: 'm2',
            role: TextMessageRole.user,
            delta: 'Two',
          ),
        ]),
        verify: (agent) => expect(agent.state.messages, [
          isA<AssistantMessage>().having((m) => m.content, 'content', 'One'),
          isA<UserMessage>().having((m) => m.content, 'content', 'Two'),
        ]),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk without delta still creates the message',
        build: buildAgent,
        act: (agent) =>
            agent.receive(const [TextMessageChunkEvent(messageId: 'm1')]),
        expect: () => [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single.content,
            'text',
            '',
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk without id never grows a message of another role',
        build: buildAgent,
        seed: () => agentState.copyWith(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
        act: (agent) =>
            agent.receive(const [TextMessageChunkEvent(delta: 'x')]),
        expect: () => const <CopilotAgentState>[],
      );

      for (final role in TextMessageRole.values) {
        blocTest<CopilotAgentBloc, CopilotAgentState>(
          'a chunk without id grows the last ${role.name} message',
          build: buildAgent,
          act: (agent) => agent.receive([
            TextMessageChunkEvent(messageId: 'm1', role: role, delta: 'Hi'),
            TextMessageChunkEvent(role: role, delta: '!'),
          ]),
          verify: (agent) => expect(agent.state.messages.single.content, 'Hi!'),
        );
      }

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk without id or prior message is ignored',
        build: buildAgent,
        act: (agent) =>
            agent.receive(const [TextMessageChunkEvent(delta: 'x')]),
        expect: () => const <CopilotAgentState>[],
      );
    });

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'unknown events leave the state unchanged',
      build: buildAgent,
      seed: () => agentState.copyWith(isRunning: true),
      act: (agent) =>
          agent.receive(const [CustomEvent(name: 'progress', value: 1)]),
      expect: () => const <CopilotAgentState>[],
    );

    group('recorded fixtures', () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'text_stream builds one assistant message',
        build: buildAgent,
        act: (agent) => agent.receive(loadFixture('text_stream').events),
        verify: (agent) {
          expect(
            agent.state.messages.single,
            isA<AssistantMessage>().having(
              (m) => m.content,
              'content',
              'Hello! Wonderful to meet you.',
            ),
          );
          expect(agent.state.error, isNull);
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'run_error keeps the runtime error',
        build: buildAgent,
        act: (agent) => agent.receive(loadFixture('run_error').events),
        verify: (agent) {
          expect(agent.state.messages, isEmpty);
          expect(
            agent.state.error,
            isA<RunErrorEvent>().having(
              (error) => error.message,
              'message',
              contains('gemini-2.5-flash'),
            ),
          );
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'dropped_connection keeps the partial reply',
        build: buildAgent,
        act: (agent) => agent.receive(loadFixture('dropped_connection').events),
        verify: (agent) {
          expect(agent.state.messages.single.content, 'Hello! Wonderful to');
          expect(agent.state.error, isNull);
        },
      );
    });
  });
}
