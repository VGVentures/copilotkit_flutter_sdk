import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';

const _start = ToolCallStartEvent(
  toolCallId: 'c1',
  toolCallName: 'showWeather',
  parentMessageId: 'm1',
);

/// Matches a state whose only tool call has [args].
Matcher _hasArgs(Object? args) => isA<CopilotAgentState>().having(
  (state) => state.toolCalls.single.args,
  'args',
  args,
);

void main() {
  group('$AgentEventReducer reduces tool calls', () {
    test('Start adds an in-progress view with empty args', () {
      final result = reduce(const [_start]);
      final view = result.state.toolCalls.single;
      expect(view.id, 'c1');
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.inProgress);
      expect(view.args, isEmpty);
      expect(view.result, isNull);
    });

    test('Start records the call on a new assistant message', () {
      final result = reduce(const [_start]);
      final message = result.state.messages.single as AssistantMessage;
      expect(message.id, 'm1');
      final call = message.toolCalls!.single;
      expect(call.id, 'c1');
      expect(call.type, 'function');
      expect(call.function.name, 'showWeather');
      expect(call.function.arguments, '');
    });

    test('Start without a parent message uses the call id', () {
      final result = reduce(const [
        ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
      ]);
      expect(result.state.messages.single.id, 'c1');
    });

    test('Start adds the call to an existing assistant message', () {
      final result = reduce(const [
        TextMessageStartEvent(messageId: 'm1'),
        TextMessageContentEvent(messageId: 'm1', delta: 'Checking'),
        _start,
        ToolCallStartEvent(
          toolCallId: 'c2',
          toolCallName: 'other',
          parentMessageId: 'm1',
        ),
      ]);
      final message = result.state.messages.single as AssistantMessage;
      expect(message.content, 'Checking');
      expect(message.toolCalls!.map((c) => c.id), ['c1', 'c2']);
      expect(result.state.toolCalls.map((v) => v.id), ['c1', 'c2']);
    });

    test('a repeated Start is ignored', () {
      final result = reduce(const [_start, _start]);
      expect(result.states, [_hasArgs(isEmpty)]);
    });

    test('Args grow the raw arguments and the parsed partial args', () {
      final result = reduce(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Li'),
        ToolCallArgsEvent(toolCallId: 'c1', delta: 'ma"}'),
      ]);
      expect(result.states, [
        _hasArgs(isEmpty),
        _hasArgs({'city': 'Li'}),
        _hasArgs({'city': 'Lima'}),
      ]);
      final message = result.state.messages.single as AssistantMessage;
      expect(message.toolCalls!.single.function.arguments, '{"city": "Lima"}');
    });

    final user = UserMessage(id: 'u1', content: 'Weather?');

    test('Args leave other messages untouched', () {
      final result = reduce(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
      ], from: agentState.copyWith(messages: [user]));
      expect(result.state.messages.first, same(user));
    });

    test('Args for an unknown call are ignored', () {
      final result = reduce(const [
        ToolCallArgsEvent(toolCallId: 'x', delta: '{}'),
      ]);
      expect(result.states, const <CopilotAgentState>[]);
    });

    test('End moves the call to executing', () {
      final result = reduce(const [_start, ToolCallEndEvent(toolCallId: 'c1')]);
      expect(result.state.toolCalls.single.status, ToolCallStatus.executing);
    });

    test('End for an unknown call is ignored', () {
      final result = reduce(const [ToolCallEndEvent(toolCallId: 'x')]);
      expect(result.states, const <CopilotAgentState>[]);
    });

    test('Result completes the call and appends a tool message', () {
      final result = reduce(const [
        _start,
        ToolCallEndEvent(toolCallId: 'c1'),
        ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'c1',
          content: '{"forecast": "sunny"}',
        ),
      ]);
      final view = result.state.toolCalls.single;
      expect(view.status, ToolCallStatus.complete);
      expect(view.result, '{"forecast": "sunny"}');
      final message = result.state.messages.last as ToolMessage;
      expect(message.id, 't1');
      expect(message.toolCallId, 'c1');
      expect(message.content, '{"forecast": "sunny"}');
    });

    test('Result for an unknown call still appends the tool message', () {
      final result = reduce(const [
        ToolCallResultEvent(messageId: 't1', toolCallId: 'x', content: 'done'),
      ]);
      expect(result.state.toolCalls, isEmpty);
      expect(result.state.messages.single, isA<ToolMessage>());
    });

    test('a repeated Result is ignored', () {
      const result = ToolCallResultEvent(
        messageId: 't1',
        toolCallId: 'c1',
        content: 'done',
      );

      expect(reduce(const [_start, result, result]).states, hasLength(2));
    });

    group('chunks', () {
      test('first chunk starts the call, later chunks grow its args', () {
        final result = reduce(const [
          ToolCallChunkEvent(
            toolCallId: 'c1',
            toolCallName: 'showWeather',
            parentMessageId: 'm1',
            delta: '{"city":',
          ),
          ToolCallChunkEvent(delta: ' "Lima"'),
          ToolCallChunkEvent(toolCallId: 'c1', delta: '}'),
        ]);
        final view = result.state.toolCalls.single;
        expect(view.name, 'showWeather');
        expect(view.args, {'city': 'Lima'});
        expect(result.state.messages.single.id, 'm1');
      });

      test('a chunk without a name for an unknown call is ignored', () {
        final result = reduce(const [
          ToolCallChunkEvent(toolCallId: 'c1', delta: '{}'),
          ToolCallChunkEvent(delta: '{}'),
        ]);
        expect(result.states, const <CopilotAgentState>[]);
      });

      test('a chunk without delta only starts the call', () {
        final result = reduce(const [
          ToolCallChunkEvent(toolCallId: 'c1', toolCallName: 'tool'),
        ]);
        expect(result.states, [_hasArgs(isEmpty)]);
      });
    });

    test('RunFinished moves calls still in progress to executing', () {
      final result = reduce(const [
        _start,
        ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'done'),
        ToolCallResultEvent(messageId: 't', toolCallId: 'c2', content: 'ok'),
        RunFinishedEvent(threadId: 't', runId: 'r'),
      ]);
      expect(result.state.toolCalls.map((v) => v.status), [
        ToolCallStatus.executing,
        ToolCallStatus.complete,
      ]);
    });

    test('frontend_tool_call fixture leaves the call executing', () {
      final result = reduce(loadFixture('frontend_tool_call').events);
      final view = result.state.toolCalls.single;
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.executing);
      expect(view.args, {'city': 'Lima'});
      expect(view.result, isNull);
    });
  });
}
