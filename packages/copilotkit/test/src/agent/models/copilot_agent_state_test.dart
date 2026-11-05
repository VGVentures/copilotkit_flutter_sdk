import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotAgentState, () {
    test('defaults to an idle, empty agent', () {
      const snapshot = CopilotAgentState(agentId: 'a', threadId: 't');

      expect(snapshot.agentId, 'a');
      expect(snapshot.threadId, 't');
      expect(snapshot.messages, isEmpty);
      expect(snapshot.sharedState, isNull);
      expect(snapshot.isRunning, isFalse);
      expect(snapshot.toolCalls, isEmpty);
      expect(snapshot.error, isNull);
    });

    test('holds the given values', () {
      const message = UserMessage(id: 'user-1', content: 'Hi');
      const toolCall = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.executing,
      );
      final error = StateError('boom');

      final snapshot = CopilotAgentState(
        agentId: 'a',
        threadId: 't',
        messages: const [message],
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
      const message = UserMessage(id: 'u1', content: 'Hi');
      CopilotAgentState snapshot({bool isRunning = false}) => CopilotAgentState(
        agentId: 'a',
        threadId: 't',
        messages: const [message],
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
        const CopilotAgentState(
          agentId: 'a',
          threadId: 't',
          toolCalls: calls,
        ).awaitingResponseIds,
        ['c1', 'c3'],
      );
      expect(
        const CopilotAgentState(
          agentId: 'a',
          threadId: 't',
        ).awaitingResponseIds,
        isEmpty,
      );
    });

    group('copyWith', () {
      test('keeps every field when nothing is passed', () {
        final error = StateError('boom');
        final snapshot = CopilotAgentState(
          agentId: 'a',
          threadId: 't',
          messages: const [UserMessage(id: 'u1', content: 'Hi')],
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
        const message = UserMessage(id: 'u1', content: 'Hi');
        const toolCall = ToolCallView(
          id: 'c',
          name: 't',
          status: ToolCallStatus.inProgress,
        );

        final copy = const CopilotAgentState(agentId: 'a', threadId: 't')
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

      test('makes the lists it is given unmodifiable', () {
        final state = const CopilotAgentState(
          agentId: 'a',
          threadId: 't',
        ).copyWith(messages: [], toolCalls: []);

        expect(
          () => state.messages.add(const UserMessage(id: 'u', content: '')),
          throwsUnsupportedError,
        );
        expect(
          () => state.toolCalls.add(
            const ToolCallView(
              id: 'c',
              name: 'n',
              status: ToolCallStatus.executing,
            ),
          ),
          throwsUnsupportedError,
        );
      });

      test('can reset state and error to null', () {
        const snapshot = CopilotAgentState(
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

    group('tool call getters', () {
      const call = ToolCall(id: 'c1', name: 'showWeather', arguments: '{}');
      const view = ToolCallView(
        id: 'c1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        result: 'sunny',
      );
      const state = CopilotAgentState(
        agentId: 'a',
        threadId: 't',
        messages: [
          AssistantMessage(id: 'm1', toolCalls: [call]),
          ToolMessage(id: 'r1', content: 'sunny', toolCallId: 'c1'),
        ],
        toolCalls: [view],
      );

      test('anyToolCall says whether it has a call', () {
        expect(state.anyToolCall('c1'), isTrue);
        expect(state.anyToolCall('c2'), isFalse);
      });

      test('toolCallsById maps each view by id', () {
        expect(state.toolCallsById, {'c1': view});
      });

      test('messageToolCalls lists the calls held by messages', () {
        expect(state.messageToolCalls, [call]);
      });

      test('toolResults maps each result by tool call id', () {
        expect(state.toolResults, {'c1': 'sunny'});
      });
    });

    group('transitions', () {
      const empty = CopilotAgentState(agentId: 'a', threadId: 't');

      test('messageAdded appends a message', () {
        const message = UserMessage(id: 'u1', content: 'Hi');

        expect(empty.messageAdded(message).messages, [message]);
      });

      test('textAppended creates the message, then grows it', () {
        final state = empty
            .textAppended('m1', ag_ui.TextMessageRole.assistant, 'Hel')
            .textAppended('m1', ag_ui.TextMessageRole.assistant, 'lo');

        expect(state.messages, [
          const AssistantMessage(id: 'm1', content: 'Hello'),
        ]);
      });

      test('toolCallStarted adds the call to its parent message', () {
        final state = empty
            .messageAdded(const AssistantMessage(id: 'm1', content: 'Sure'))
            .toolCallStarted('c1', 'showWeather', 'm1');

        expect(state.messages, [
          const AssistantMessage(
            id: 'm1',
            content: 'Sure',
            toolCalls: [ToolCall(id: 'c1', name: 'showWeather', arguments: '')],
          ),
        ]);
        expect(state.toolCalls, [
          const ToolCallView(
            id: 'c1',
            name: 'showWeather',
            status: ToolCallStatus.inProgress,
          ),
        ]);
      });

      test('toolCallStarted adds a message named after a parent it lacks', () {
        final state = empty.toolCallStarted('c1', 'showWeather', 'm1');

        expect(state.messages, [
          const AssistantMessage(
            id: 'm1',
            toolCalls: [ToolCall(id: 'c1', name: 'showWeather', arguments: '')],
          ),
        ]);
        expect(state.toolCalls, [
          const ToolCallView(
            id: 'c1',
            name: 'showWeather',
            status: ToolCallStatus.inProgress,
          ),
        ]);
        final message = state.messages.single as AssistantMessage;
        expect(
          () => message.toolCalls.add(message.toolCalls.single),
          throwsUnsupportedError,
        );
      });

      test('toolCallStarted drops a repeated id', () {
        final state = empty.toolCallStarted('c1', 'showWeather', null);

        expect(state.toolCallStarted('c1', 'other', null), state);
      });

      test('toolArgumentsAppended appends the raw and sets the parsed '
          'arguments', () {
        final parsed = <String>[];
        final state = empty
            .toolCallStarted('c1', 'showWeather', null)
            .toolArgumentsAppended(
              'c1',
              '{"city": ',
              parse: (arguments) {
                parsed.add(arguments);
                return const {};
              },
            )
            .toolArgumentsAppended(
              'c1',
              '"Lima"}',
              parse: (arguments) {
                parsed.add(arguments);
                return const {'city': 'Lima'};
              },
            );

        expect(state.messageToolCalls.single.arguments, '{"city": "Lima"}');
        expect(state.toolCalls.single.args, const {'city': 'Lima'});
        expect(parsed, ['{"city": ', '{"city": "Lima"}']);
      });

      test('toolArgumentsAppended ignores an unknown call', () {
        expect(
          empty.toolArgumentsAppended('c1', '{}', parse: (_) => const {}),
          empty,
        );
      });

      test('toolCallCompleted adds the result once', () {
        final state = empty
            .toolCallStarted('c1', 'showWeather', null)
            .toolCallCompleted('r1', 'c1', 'sunny');

        expect(state.toolResults, {'c1': 'sunny'});
        expect(state.toolCalls.single.isComplete, isTrue);
        expect(state.toolCallCompleted('r1', 'c1', 'sunny'), state);
      });

      test('toolCallsMarkedExecuting moves calls in progress on', () {
        final state = empty.toolCallStarted('c1', 'showWeather', null);

        expect(
          state.toolCallsMarkedExecuting().toolCalls.single.isExecuting,
          isTrue,
        );
        expect(empty.toolCallsMarkedExecuting(), empty);
      });

      test('toolCallUpdated keeps the state when nothing changes', () {
        final state = empty.toolCallStarted('c1', 'showWeather', null);

        expect(state.toolCallUpdated('c1', (view) => view), state);
        expect(
          state.toolCallUpdated('c2', (view) => view.completed('')),
          state,
        );
      });

      test('messagesReplaced rebuilds the tool calls from the messages', () {
        final state = empty.messagesReplaced(const [
          AssistantMessage(
            id: 'm1',
            toolCalls: [
              ToolCall(id: 'c1', name: 'a', arguments: '{"x": 1}'),
              ToolCall(id: 'c2', name: 'b', arguments: ''),
            ],
          ),
          ToolMessage(id: 'r1', content: 'done', toolCallId: 'c1'),
        ], parse: (arguments) => {'raw': arguments});

        expect(state.toolCalls, const [
          ToolCallView(
            id: 'c1',
            name: 'a',
            status: ToolCallStatus.complete,
            args: {'raw': '{"x": 1}'},
            result: 'done',
          ),
          ToolCallView(
            id: 'c2',
            name: 'b',
            status: ToolCallStatus.executing,
            args: {'raw': ''},
          ),
        ]);
      });

      test('sharedStateReplaced sets an unmodifiable state, or clears it', () {
        final state = empty.sharedStateReplaced({'a': 1});

        expect(state.sharedState, const SharedState({'a': 1}));
        expect(
          () => state.sharedState!.toJson()['b'] = 2,
          throwsUnsupportedError,
        );
        expect(state.sharedStateReplaced(null).sharedState, isNull);
      });
    });
  });
}
