import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/agent_state.dart';
import 'package:test/test.dart';

import '../../helpers/agent_reducer.dart';
import '../../helpers/fixtures.dart';

void main() {
  group('CopilotAgent reduces', () {
    group('lifecycle', () {
      // The client owns isRunning for the whole turn (runs plus tool
      // handlers), so lifecycle events never toggle it.
      test('RunStarted clears the previous error, not isRunning', () async {
        const previous = AgentState(isRunning: true, error: 'boom');

        final snapshot = await reduce(
          previous,
          RunStartedEvent(threadId: 't', runId: 'r'),
        );

        expect(snapshot.isRunning, isTrue);
        expect(snapshot.error, isNull);
      });

      test('RunFinished leaves isRunning to the client', () async {
        const running = AgentState(isRunning: true);

        expect(
          await reduce(
            running,
            const RunFinishedEvent(threadId: 't', runId: 'r'),
          ),
          same(running),
        );
      });

      test('RunError keeps the error and leaves isRunning', () async {
        const error = RunErrorEvent(message: 'Bad key', code: 'AUTH');

        final snapshot = await reduce(const AgentState(isRunning: true), error);

        expect(snapshot.isRunning, isTrue);
        expect(snapshot.error, same(error));
      });

      test('steps leave the snapshot unchanged', () async {
        const running = AgentState(isRunning: true);

        expect(
          await reduce(running, const StepStartedEvent(stepName: 's')),
          same(running),
        );
        expect(
          await reduce(running, const StepFinishedEvent(stepName: 's')),
          same(running),
        );
      });

      test('keeps messages and state across the run', () async {
        final user = UserMessage(id: 'u1', content: 'Hi');
        final initial = AgentState(
          messages: [user],
          sharedState: const {'a': 1},
        );

        final snapshot = await replay([
          RunStartedEvent(threadId: 't', runId: 'r'),
          const RunFinishedEvent(threadId: 't', runId: 'r'),
        ], initial);

        expect(snapshot.messages, [user]);
        expect(snapshot.sharedState, {'a': 1});
      });
    });

    group('text messages', () {
      test('Start appends an empty message with the given role', () async {
        final snapshot = await reduce(
          const AgentState(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        final message = snapshot.messages.single;
        expect(message, isA<AssistantMessage>());
        expect(message.id, 'm1');
        expect(message.content, '');
      });

      test('Content grows the message text on every delta', () async {
        var snapshot = await reduce(
          const AgentState(),
          const TextMessageStartEvent(messageId: 'm1'),
        );
        final texts = <String?>[];
        for (final delta in ['Hel', 'lo', ' there']) {
          snapshot = await reduce(
            snapshot,
            TextMessageContentEvent(messageId: 'm1', delta: delta),
          );
          texts.add(snapshot.messages.single.content);
        }

        expect(texts, ['Hel', 'Hello', 'Hello there']);
      });

      test('Content does not mutate earlier snapshots', () async {
        final started = await reduce(
          const AgentState(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        await reduce(
          started,
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        );

        expect(started.messages.single.content, '');
      });

      test('Content appends to the right message by id', () async {
        final user = UserMessage(id: 'u1', content: 'Hi');

        final snapshot = await replay([
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'First'),
          const TextMessageStartEvent(messageId: 'm2'),
          const TextMessageContentEvent(messageId: 'm2', delta: 'Second'),
          const TextMessageContentEvent(messageId: 'm1', delta: '!'),
        ], AgentState(messages: [user]));

        expect(snapshot.messages.map((m) => m.content), [
          'Hi',
          'First!',
          'Second',
        ]);
      });

      test('Content without a Start creates an assistant message', () async {
        final snapshot = await reduce(
          const AgentState(),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        );

        expect(snapshot.messages.single, isA<AssistantMessage>());
        expect(snapshot.messages.single.content, 'Hi');
      });

      test('End leaves the snapshot unchanged', () async {
        final started = await reduce(
          const AgentState(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        expect(
          await reduce(started, const TextMessageEndEvent(messageId: 'm1')),
          same(started),
        );
      });

      test('Start keeps non-assistant roles', () async {
        final snapshot = await replay(const [
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

        expect(snapshot.messages, [
          isA<UserMessage>().having((m) => m.content, 'content', 'Hi'),
          isA<SystemMessage>().having((m) => m.content, 'content', 'Be nice'),
          isA<DeveloperMessage>().having((m) => m.content, 'content', 'Debug'),
        ]);
      });

      test('Content aimed at a non-text message leaves it unchanged', () async {
        const tool = ToolMessage(id: 'x', content: 'result', toolCallId: 'c');

        final snapshot = await reduce(
          const AgentState(messages: [tool]),
          const TextMessageContentEvent(messageId: 'x', delta: 'Hi'),
        );

        expect(snapshot.messages.single, same(tool));
      });

      test('Content keeps the name of the message', () async {
        final snapshot = await replay(const [
          TextMessageStartEvent(messageId: 'm1', name: 'helper'),
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]);

        expect(snapshot.messages.single.name, 'helper');
      });
    });

    group('text message chunks', () {
      test('first chunk creates the message, later chunks grow it', () async {
        final snapshot = await replay(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'Hel'),
          TextMessageChunkEvent(delta: 'lo'),
          TextMessageChunkEvent(messageId: 'm1', delta: '!'),
        ]);

        final message = snapshot.messages.single;
        expect(message, isA<AssistantMessage>());
        expect(message.id, 'm1');
        expect(message.content, 'Hello!');
      });

      test('a chunk with a new id starts a new message', () async {
        final snapshot = await replay(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'One'),
          TextMessageChunkEvent(
            messageId: 'm2',
            role: TextMessageRole.user,
            delta: 'Two',
          ),
        ]);

        expect(snapshot.messages, [
          isA<AssistantMessage>().having((m) => m.content, 'content', 'One'),
          isA<UserMessage>().having((m) => m.content, 'content', 'Two'),
        ]);
      });

      test('a chunk without delta still creates the message', () async {
        final snapshot = await reduce(
          const AgentState(),
          const TextMessageChunkEvent(messageId: 'm1'),
        );

        expect(snapshot.messages.single.content, '');
      });

      test(
        'a chunk without id never grows a message of another role',
        () async {
          final user = await replay(const [
            TextMessageChunkEvent(
              messageId: 'u1',
              role: TextMessageRole.user,
              delta: 'Hi',
            ),
          ]);

          expect(
            await reduce(user, const TextMessageChunkEvent(delta: 'x')),
            same(user),
          );
        },
      );

      for (final role in TextMessageRole.values) {
        test(
          'a chunk without id grows the last ${role.name} message',
          () async {
            final snapshot = await replay([
              TextMessageChunkEvent(messageId: 'm1', role: role, delta: 'Hi'),
              TextMessageChunkEvent(role: role, delta: '!'),
            ]);

            expect(snapshot.messages.single.content, 'Hi!');
          },
        );
      }

      test('a chunk without id or prior message is ignored', () async {
        const empty = AgentState();

        expect(
          await reduce(empty, const TextMessageChunkEvent(delta: 'x')),
          same(empty),
        );
      });
    });

    test('unknown events leave the snapshot unchanged', () async {
      const snapshot = AgentState(isRunning: true);

      expect(
        await reduce(snapshot, const CustomEvent(name: 'progress', value: 1)),
        same(snapshot),
      );
    });

    group('recorded fixtures', () {
      test('text_stream builds one assistant message', () async {
        final snapshot = await replay(loadFixture('text_stream').events);

        final message = snapshot.messages.single;
        expect(message, isA<AssistantMessage>());
        expect(message.content, 'Hello! Wonderful to meet you.');
        expect(snapshot.error, isNull);
      });

      test('run_error keeps the runtime error', () async {
        final snapshot = await replay(loadFixture('run_error').events);

        expect(snapshot.messages, isEmpty);
        expect(
          snapshot.error,
          isA<RunErrorEvent>().having(
            (error) => error.message,
            'message',
            contains('gemini-2.5-flash'),
          ),
        );
      });

      test('dropped_connection keeps the partial reply', () async {
        final snapshot = await replay(loadFixture('dropped_connection').events);

        expect(snapshot.messages.single.content, 'Hello! Wonderful to');
        expect(snapshot.error, isNull);
      });
    });
  });
}
