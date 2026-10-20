import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotKitAgentState, () {
    test('defaults to an idle, empty agent', () {
      const snapshot = CopilotKitAgentState(agentId: 'a', threadId: 't');

      expect(snapshot.agentId, 'a');
      expect(snapshot.threadId, 't');
      expect(snapshot.messages, isEmpty);
      expect(snapshot.sharedState, isNull);
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

      final snapshot = CopilotKitAgentState(
        agentId: 'a',
        threadId: 't',
        messages: [message],
        sharedState: const SharedState({'count': 1}),
        isRunning: true,
        toolCalls: const [toolCall],
        error: error,
      );

      expect(snapshot.messages, [message]);
      expect(snapshot.sharedState, const SharedState({'count': 1}));
      expect(snapshot.isRunning, isTrue);
      expect(snapshot.toolCalls, [toolCall]);
      expect(snapshot.error, same(error));
    });

    test('supports value equality', () {
      final message = UserMessage(id: 'u1', content: 'Hi');
      CopilotKitAgentState snapshot({bool isRunning = false}) =>
          CopilotKitAgentState(
            agentId: 'a',
            threadId: 't',
            messages: [message],
            sharedState: const SharedState({'a': 1}),
            isRunning: isRunning,
            error: 'boom',
          );

      expect(snapshot(), snapshot());
      expect(snapshot(), isNot(snapshot(isRunning: true)));
    });

    test('lists the tool calls that await a response, in call order', () {
      const calls = [
        ToolCallView(
          id: 'c1',
          name: 'confirm',
          status: ToolCallStatus.executing,
          awaitingResponse: true,
        ),
        ToolCallView(id: 'c2', name: 'other', status: ToolCallStatus.executing),
        ToolCallView(
          id: 'c3',
          name: 'confirm',
          status: ToolCallStatus.executing,
          awaitingResponse: true,
        ),
      ];

      expect(
        const CopilotKitAgentState(
          agentId: 'a',
          threadId: 't',
          toolCalls: calls,
        ).awaitingResponseIds,
        ['c1', 'c3'],
      );
      expect(
        const CopilotKitAgentState(
          agentId: 'a',
          threadId: 't',
        ).awaitingResponseIds,
        isEmpty,
      );
    });

    group('copyWith', () {
      test('keeps every field when nothing is passed', () {
        final error = StateError('boom');
        final snapshot = CopilotKitAgentState(
          agentId: 'a',
          threadId: 't',
          messages: [UserMessage(id: 'u1', content: 'Hi')],
          sharedState: const SharedState({'a': 1}),
          isRunning: true,
          toolCalls: const [
            ToolCallView(id: 'c', name: 't', status: ToolCallStatus.complete),
          ],
          error: error,
        );

        final copy = snapshot.copyWith();

        expect(copy.agentId, 'a');
        expect(copy.threadId, 't');
        expect(copy.messages, same(snapshot.messages));
        expect(copy.sharedState, same(snapshot.sharedState));
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

        final copy = const CopilotKitAgentState(agentId: 'a', threadId: 't')
            .copyWith(
              messages: [message],
              sharedState: () => const SharedState({'a': 1}),
              isRunning: true,
              toolCalls: [toolCall],
              error: () => 'boom',
            );

        expect(copy.messages, [message]);
        expect(copy.sharedState, const SharedState({'a': 1}));
        expect(copy.isRunning, isTrue);
        expect(copy.toolCalls, [toolCall]);
        expect(copy.error, 'boom');
      });

      test('can reset state and error to null', () {
        const snapshot = CopilotKitAgentState(
          agentId: 'a',
          threadId: 't',
          sharedState: SharedState({'a': 1}),
          error: 'boom',
        );

        final copy = snapshot.copyWith(
          sharedState: () => null,
          error: () => null,
        );

        expect(copy.sharedState, isNull);
        expect(copy.error, isNull);
      });
    });
  });
}
