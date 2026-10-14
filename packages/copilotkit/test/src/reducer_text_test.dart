import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_snapshot.dart';
import 'package:copilotkit/src/reducer.dart';
import 'package:test/test.dart';

AgentSnapshot _replay(List<BaseEvent> events, [AgentSnapshot? initial]) =>
    events.fold(initial ?? const AgentSnapshot(), reduceAgentEvent);

void main() {
  group('reduceAgentEvent', () {
    group('lifecycle', () {
      test('RunStarted sets isRunning and clears the previous error', () {
        const previous = AgentSnapshot(error: 'boom');

        final snapshot = reduceAgentEvent(
          previous,
          RunStartedEvent(threadId: 't', runId: 'r'),
        );

        expect(snapshot.isRunning, isTrue);
        expect(snapshot.error, isNull);
      });

      test('RunFinished clears isRunning', () {
        final snapshot = _replay([
          RunStartedEvent(threadId: 't', runId: 'r'),
          const RunFinishedEvent(threadId: 't', runId: 'r'),
        ]);

        expect(snapshot.isRunning, isFalse);
        expect(snapshot.error, isNull);
      });

      test('RunError clears isRunning and keeps the error', () {
        const error = RunErrorEvent(message: 'Bad key', code: 'AUTH');

        final snapshot = _replay([
          RunStartedEvent(threadId: 't', runId: 'r'),
          error,
        ]);

        expect(snapshot.isRunning, isFalse);
        expect(snapshot.error, same(error));
      });

      test('steps leave the snapshot unchanged', () {
        const running = AgentSnapshot(isRunning: true);

        expect(
          reduceAgentEvent(running, const StepStartedEvent(stepName: 's')),
          same(running),
        );
        expect(
          reduceAgentEvent(running, const StepFinishedEvent(stepName: 's')),
          same(running),
        );
      });

      test('keeps messages and state across the run', () {
        final user = UserMessage(id: 'u1', content: 'Hi');
        final initial = AgentSnapshot(messages: [user], state: const {'a': 1});

        final snapshot = _replay([
          RunStartedEvent(threadId: 't', runId: 'r'),
          const RunFinishedEvent(threadId: 't', runId: 'r'),
        ], initial);

        expect(snapshot.messages, [user]);
        expect(snapshot.state, {'a': 1});
      });
    });

    group('text messages', () {
      test('Start appends an empty message with the given role', () {
        final snapshot = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        final message = snapshot.messages.single;
        expect(message, isA<AssistantMessage>());
        expect(message.id, 'm1');
        expect(message.content, '');
      });

      test('Content grows the message text on every delta', () {
        var snapshot = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageStartEvent(messageId: 'm1'),
        );
        final texts = <String?>[];
        for (final delta in ['Hel', 'lo', ' there']) {
          snapshot = reduceAgentEvent(
            snapshot,
            TextMessageContentEvent(messageId: 'm1', delta: delta),
          );
          texts.add(snapshot.messages.single.content);
        }

        expect(texts, ['Hel', 'Hello', 'Hello there']);
      });

      test('Content does not mutate earlier snapshots', () {
        final started = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        reduceAgentEvent(
          started,
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        );

        expect(started.messages.single.content, '');
      });

      test('Content appends to the right message by id', () {
        final user = UserMessage(id: 'u1', content: 'Hi');

        final snapshot = _replay([
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'First'),
          const TextMessageStartEvent(messageId: 'm2'),
          const TextMessageContentEvent(messageId: 'm2', delta: 'Second'),
          const TextMessageContentEvent(messageId: 'm1', delta: '!'),
        ], AgentSnapshot(messages: [user]));

        expect(snapshot.messages.map((m) => m.content), [
          'Hi',
          'First!',
          'Second',
        ]);
      });

      test('Content without a Start creates an assistant message', () {
        final snapshot = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        );

        expect(snapshot.messages.single, isA<AssistantMessage>());
        expect(snapshot.messages.single.content, 'Hi');
      });

      test('End leaves the snapshot unchanged', () {
        final started = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageStartEvent(messageId: 'm1'),
        );

        expect(
          reduceAgentEvent(started, const TextMessageEndEvent(messageId: 'm1')),
          same(started),
        );
      });

      test('Start keeps non-assistant roles', () {
        final snapshot = _replay(const [
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

      test('Content aimed at a non-text message leaves it unchanged', () {
        const tool = ToolMessage(id: 'x', content: 'result', toolCallId: 'c');

        final snapshot = reduceAgentEvent(
          const AgentSnapshot(messages: [tool]),
          const TextMessageContentEvent(messageId: 'x', delta: 'Hi'),
        );

        expect(snapshot.messages.single, same(tool));
      });

      test('Content keeps the name of the message', () {
        final snapshot = _replay(const [
          TextMessageStartEvent(messageId: 'm1', name: 'helper'),
          TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        ]);

        expect(snapshot.messages.single.name, 'helper');
      });
    });

    group('text message chunks', () {
      test('first chunk creates the message, later chunks grow it', () {
        final snapshot = _replay(const [
          TextMessageChunkEvent(messageId: 'm1', delta: 'Hel'),
          TextMessageChunkEvent(delta: 'lo'),
          TextMessageChunkEvent(messageId: 'm1', delta: '!'),
        ]);

        final message = snapshot.messages.single;
        expect(message, isA<AssistantMessage>());
        expect(message.id, 'm1');
        expect(message.content, 'Hello!');
      });

      test('a chunk with a new id starts a new message', () {
        final snapshot = _replay(const [
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

      test('a chunk without delta still creates the message', () {
        final snapshot = reduceAgentEvent(
          const AgentSnapshot(),
          const TextMessageChunkEvent(messageId: 'm1'),
        );

        expect(snapshot.messages.single.content, '');
      });

      test('a chunk without id or prior message is ignored', () {
        const empty = AgentSnapshot();

        expect(
          reduceAgentEvent(empty, const TextMessageChunkEvent(delta: 'x')),
          same(empty),
        );
      });
    });

    test('unknown events leave the snapshot unchanged', () {
      const snapshot = AgentSnapshot(isRunning: true);

      expect(
        reduceAgentEvent(
          snapshot,
          const CustomEvent(name: 'progress', value: 1),
        ),
        same(snapshot),
      );
    });
  });
}
