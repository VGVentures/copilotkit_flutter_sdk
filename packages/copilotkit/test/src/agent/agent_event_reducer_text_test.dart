import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/run_error.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:test/test.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';

void main() {
  group('$AgentEventReducer reduces', () {
    group('lifecycle', () {
      final user = UserMessage(id: 'u1', content: 'Hi');

      // The client owns isRunning for the whole turn (runs plus tool
      // handlers), so lifecycle events never toggle it.
      test('RunStarted clears the previous error, not isRunning', () {
        final result = reduce([
          RunStartedEvent(threadId: 't', runId: 'r'),
        ], from: agentState.copyWith(isRunning: true, error: () => 'boom'));
        expect(result.states, [agentState.copyWith(isRunning: true)]);
      });

      test('RunFinished leaves isRunning to the client', () {
        final result = reduce(const [
          RunFinishedEvent(threadId: 't', runId: 'r'),
        ], from: agentState.copyWith(isRunning: true));
        expect(result.states, const <CopilotAgentState>[]);
      });

      test('RunError keeps the error and leaves isRunning', () {
        final result = reduce(const [
          RunErrorEvent(message: 'Bad key', code: 'AUTH'),
        ], from: agentState.copyWith(isRunning: true));
        expect(result.states, [
          agentState.copyWith(
            isRunning: true,
            error: () => const RunError(message: 'Bad key', code: 'AUTH'),
          ),
        ]);
      });

      test('steps leave the state unchanged', () {
        final result = reduce(const [
          StepStartedEvent(stepName: 's'),
          StepFinishedEvent(stepName: 's'),
        ], from: agentState.copyWith(isRunning: true));
        expect(result.states, const <CopilotAgentState>[]);
      });

      test('keeps messages and state across the run', () {
        final result = reduce(
          [
            RunStartedEvent(threadId: 't', runId: 'r'),
            const RunFinishedEvent(threadId: 't', runId: 'r'),
          ],
          from: agentState.copyWith(
            messages: [user],
            sharedState: () => const SharedState({'a': 1}),
            error: () => 'boom',
          ),
        );
        expect(result.states, [
          agentState.copyWith(
            messages: [user],
            sharedState: () => const SharedState({'a': 1}),
          ),
        ]);
      });
    });

    group('text messages', () {
      test('Start appends an empty message with the given role', () {
        final result = reduce(const [TextMessageStartEvent(messageId: 'm1')]);
        expect(result.states, [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single,
            'message',
            isA<AssistantMessage>()
                .having((m) => m.id, 'id', 'm1')
                .having((m) => m.content, 'content', ''),
          ),
        ]);
      });

      test('Content grows the message text on every delta', () {
        final result = reduce([
          const TextMessageStartEvent(messageId: 'm1'),
          for (final delta in ['Hel', 'lo', ' there'])
            TextMessageContentEvent(messageId: 'm1', delta: delta),
        ]);
        expect(result.states.skip(1), [
          for (final text in ['Hel', 'Hello', 'Hello there'])
            isA<CopilotAgentState>().having(
              (state) => state.messages.single.content,
              'text',
              text,
            ),
        ]);
      });

      final started = agentState.copyWith(
        messages: [const AssistantMessage(id: 'm1', content: '')],
      );

      test('Content does not mutate earlier states', () {
        reduce(const [
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ], from: started);
        expect(started.messages.single.content, '');
      });

      test('Content appends to the right message by id', () {
        final result = reduce(
          const [
            TextMessageStartEvent(messageId: 'm1'),
            TextMessageContentEvent(messageId: 'm1', delta: 'First'),
            TextMessageStartEvent(messageId: 'm2'),
            TextMessageContentEvent(messageId: 'm2', delta: 'Second'),
            TextMessageContentEvent(messageId: 'm1', delta: '!'),
          ],
          from: agentState.copyWith(
            messages: [UserMessage(id: 'u1', content: 'Hi')],
          ),
        );
        expect(result.state.messages.map((m) => m.content), [
          'Hi',
          'First!',
          'Second',
        ]);
      });

      test('Content without a Start creates an assistant message', () {
        final result = reduce(const [
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]);
        expect(result.states, [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single,
            'message',
            isA<AssistantMessage>().having((m) => m.content, 'content', 'Hi'),
          ),
        ]);
      });

      test('End leaves the state unchanged', () {
        final result = reduce(const [
          TextMessageEndEvent(messageId: 'm1'),
        ], from: started);
        expect(result.states, const <CopilotAgentState>[]);
      });

      test('Start keeps non-assistant roles', () {
        final result = reduce(const [
          TextMessageStartEvent(messageId: 'u', role: TextMessageRole.user),
          TextMessageContentEvent(messageId: 'u', delta: 'Hi'),
          TextMessageStartEvent(messageId: 's', role: TextMessageRole.system),
          TextMessageContentEvent(messageId: 's', delta: 'Be nice'),
          TextMessageStartEvent(
            messageId: 'd',
            role: TextMessageRole.developer,
          ),
          TextMessageContentEvent(messageId: 'd', delta: 'Debug'),
        ]);
        expect(result.state.messages, [
          isA<UserMessage>().having((m) => m.content, 'content', 'Hi'),
          isA<SystemMessage>().having((m) => m.content, 'content', 'Be nice'),
          isA<DeveloperMessage>().having((m) => m.content, 'content', 'Debug'),
        ]);
      });

      test('Content aimed at a non-text message leaves it unchanged', () {
        final result = reduce(
          const [TextMessageContentEvent(messageId: 'x', delta: 'Hi')],
          from: agentState.copyWith(
            messages: const [
              ToolMessage(id: 'x', content: 'result', toolCallId: 'c'),
            ],
          ),
        );
        expect(
          result.state.messages.single,
          isA<ToolMessage>().having((m) => m.content, 'content', 'result'),
        );
      });

      test('Content keeps the name of the message', () {
        final result = reduce(const [
          TextMessageStartEvent(messageId: 'm1', name: 'helper'),
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]);
        expect(result.state.messages.single.name, 'helper');
      });
    });

    group('text message chunks', () {
      test('first chunk creates the message, later chunks grow it', () {
        final result = reduce(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'Hel'),
          TextMessageChunkEvent(delta: 'lo'),
          TextMessageChunkEvent(messageId: 'm1', delta: '!'),
        ]);
        expect(
          result.state.messages.single,
          isA<AssistantMessage>()
              .having((m) => m.id, 'id', 'm1')
              .having((m) => m.content, 'content', 'Hello!'),
        );
      });

      test('a chunk with a new id starts a new message', () {
        final result = reduce(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'One'),
          TextMessageChunkEvent(
            messageId: 'm2',
            role: TextMessageRole.user,
            delta: 'Two',
          ),
        ]);
        expect(result.state.messages, [
          isA<AssistantMessage>().having((m) => m.content, 'content', 'One'),
          isA<UserMessage>().having((m) => m.content, 'content', 'Two'),
        ]);
      });

      test('a chunk without delta still creates the message', () {
        final result = reduce(const [TextMessageChunkEvent(messageId: 'm1')]);
        expect(result.states, [
          isA<CopilotAgentState>().having(
            (state) => state.messages.single.content,
            'text',
            '',
          ),
        ]);
      });

      test('a chunk without id never grows a message of another role', () {
        final result = reduce(
          const [TextMessageChunkEvent(delta: 'x')],
          from: agentState.copyWith(
            messages: [UserMessage(id: 'u1', content: 'Hi')],
          ),
        );
        expect(result.states, const <CopilotAgentState>[]);
      });

      for (final role in TextMessageRole.values) {
        test('a chunk without id grows the last ${role.name} message', () {
          final result = reduce([
            TextMessageChunkEvent(messageId: 'm1', role: role, delta: 'Hi'),
            TextMessageChunkEvent(role: role, delta: '!'),
          ]);
          expect(result.state.messages.single.content, 'Hi!');
        });
      }

      test('a chunk without id or prior message is ignored', () {
        final result = reduce(const [TextMessageChunkEvent(delta: 'x')]);
        expect(result.states, const <CopilotAgentState>[]);
      });
    });

    test('unknown events leave the state unchanged', () {
      final result = reduce(const [
        CustomEvent(name: 'progress', value: 1),
      ], from: agentState.copyWith(isRunning: true));
      expect(result.states, const <CopilotAgentState>[]);
    });

    group('recorded fixtures', () {
      test('text_stream builds one assistant message', () {
        final result = reduce(loadFixture('text_stream').events);
        expect(
          result.state.messages.single,
          isA<AssistantMessage>().having(
            (m) => m.content,
            'content',
            'Hello! Wonderful to meet you.',
          ),
        );
        expect(result.state.error, isNull);
      });

      test('run_error keeps the runtime error', () {
        final result = reduce(loadFixture('run_error').events);
        expect(result.state.messages, isEmpty);
        expect(
          result.state.error,
          isA<RunError>().having(
            (error) => error.message,
            'message',
            contains('gemini-2.5-flash'),
          ),
        );
      });

      test('dropped_connection keeps the partial reply', () {
        final result = reduce(loadFixture('dropped_connection').events);
        expect(result.state.messages.single.content, 'Hello! Wonderful to');
        expect(result.state.error, isNull);
      });
    });
  });
}
