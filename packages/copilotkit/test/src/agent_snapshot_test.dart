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
  });
}
