import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(AgentSnapshot, () {
    test('defaults to an idle, empty agent', () {
      const snapshot = AgentSnapshot();

      expect(snapshot.messages, isEmpty);
      expect(snapshot.state, isNull);
      expect(snapshot.isRunning, isFalse);
      expect(snapshot.toolCalls, isEmpty);
      expect(snapshot.error, isNull);
    });

    test('holds the given values', () {
      final message = UserMessage(id: 'user-1', content: 'Hi');
      const toolCall = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.executing,
      );
      final error = StateError('boom');

      final snapshot = AgentSnapshot(
        messages: [message],
        state: const {'count': 1},
        isRunning: true,
        toolCalls: const [toolCall],
        error: error,
      );

      expect(snapshot.messages, [message]);
      expect(snapshot.state, {'count': 1});
      expect(snapshot.isRunning, isTrue);
      expect(snapshot.toolCalls, [toolCall]);
      expect(snapshot.error, same(error));
    });

    test('supports value equality', () {
      final message = UserMessage(id: 'u1', content: 'Hi');
      AgentSnapshot snapshot({bool isRunning = false}) => AgentSnapshot(
        messages: [message],
        state: const {'a': 1},
        isRunning: isRunning,
        error: 'boom',
      );

      expect(snapshot(), snapshot());
      expect(snapshot(), isNot(snapshot(isRunning: true)));
    });

    group('copyWith', () {
      test('keeps every field when nothing is passed', () {
        final error = StateError('boom');
        final snapshot = AgentSnapshot(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
          state: const {'a': 1},
          isRunning: true,
          toolCalls: const [
            ToolCallView(id: 'c', name: 't', status: ToolCallStatus.complete),
          ],
          error: error,
        );

        final copy = snapshot.copyWith();

        expect(copy.messages, same(snapshot.messages));
        expect(copy.state, same(snapshot.state));
        expect(copy.isRunning, isTrue);
        expect(copy.toolCalls, same(snapshot.toolCalls));
        expect(copy.error, same(error));
      });

      test('replaces the given fields', () {
        final message = UserMessage(id: 'u1', content: 'Hi');
        const toolCall = ToolCallView(
          id: 'c',
          name: 't',
          status: ToolCallStatus.inProgress,
        );

        final copy = const AgentSnapshot().copyWith(
          messages: [message],
          state: () => const {'a': 1},
          isRunning: true,
          toolCalls: [toolCall],
          error: () => 'boom',
        );

        expect(copy.messages, [message]);
        expect(copy.state, {'a': 1});
        expect(copy.isRunning, isTrue);
        expect(copy.toolCalls, [toolCall]);
        expect(copy.error, 'boom');
      });

      test('can reset state and error to null', () {
        const snapshot = AgentSnapshot(state: {'a': 1}, error: 'boom');

        final copy = snapshot.copyWith(state: () => null, error: () => null);

        expect(copy.state, isNull);
        expect(copy.error, isNull);
      });
    });
  });
}
