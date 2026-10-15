import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/agent_snapshot.dart';
import 'package:copilotkit/src/agent/reducer.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

AgentSnapshot _replay(List<BaseEvent> events, [AgentSnapshot? initial]) =>
    events.fold(initial ?? const AgentSnapshot(), reduceAgentEvent);

const _start = ToolCallStartEvent(
  toolCallId: 'c1',
  toolCallName: 'showWeather',
  parentMessageId: 'm1',
);

void main() {
  group('reduceAgentEvent tool calls', () {
    test('Start adds an in-progress view with empty args', () {
      final snapshot = reduceAgentEvent(const AgentSnapshot(), _start);

      final view = snapshot.toolCalls.single;
      expect(view.id, 'c1');
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.inProgress);
      expect(view.args, isEmpty);
      expect(view.result, isNull);
    });

    test('Start records the call on a new assistant message', () {
      final snapshot = reduceAgentEvent(const AgentSnapshot(), _start);

      final message = snapshot.messages.single as AssistantMessage;
      expect(message.id, 'm1');
      final call = message.toolCalls!.single;
      expect(call.id, 'c1');
      expect(call.type, 'function');
      expect(call.function.name, 'showWeather');
      expect(call.function.arguments, '');
    });

    test('Start without a parent message uses the call id', () {
      final snapshot = reduceAgentEvent(
        const AgentSnapshot(),
        const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
      );

      expect(snapshot.messages.single.id, 'c1');
    });

    test('Start adds the call to an existing assistant message', () {
      final snapshot = _replay(const [
        TextMessageStartEvent(messageId: 'm1'),
        TextMessageContentEvent(messageId: 'm1', delta: 'Checking'),
        _start,
        ToolCallStartEvent(
          toolCallId: 'c2',
          toolCallName: 'other',
          parentMessageId: 'm1',
        ),
      ]);

      final message = snapshot.messages.single as AssistantMessage;
      expect(message.content, 'Checking');
      expect(message.toolCalls!.map((c) => c.id), ['c1', 'c2']);
      expect(snapshot.toolCalls.map((v) => v.id), ['c1', 'c2']);
    });

    test('a repeated Start is ignored', () {
      final started = reduceAgentEvent(const AgentSnapshot(), _start);

      expect(reduceAgentEvent(started, _start), same(started));
    });

    test('Args grow the raw arguments and the parsed partial args', () {
      final started = reduceAgentEvent(const AgentSnapshot(), _start);
      final partial = reduceAgentEvent(
        started,
        const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Li'),
      );
      final complete = reduceAgentEvent(
        partial,
        const ToolCallArgsEvent(toolCallId: 'c1', delta: 'ma"}'),
      );

      expect(partial.toolCalls.single.args, {'city': 'Li'});
      expect(complete.toolCalls.single.args, {'city': 'Lima'});
      final call =
          (complete.messages.single as AssistantMessage).toolCalls!.single;
      expect(call.function.arguments, '{"city": "Lima"}');
      expect(started.toolCalls.single.args, isEmpty);
    });

    test('Args leave other messages untouched', () {
      final user = UserMessage(id: 'u1', content: 'Weather?');

      final snapshot = _replay(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
      ], AgentSnapshot(messages: [user]));

      expect(snapshot.messages.first, same(user));
    });

    test('Args for an unknown call are ignored', () {
      const snapshot = AgentSnapshot();

      expect(
        reduceAgentEvent(
          snapshot,
          const ToolCallArgsEvent(toolCallId: 'x', delta: '{}'),
        ),
        same(snapshot),
      );
    });

    test('End moves the call to executing', () {
      final snapshot = _replay(const [
        _start,
        ToolCallEndEvent(toolCallId: 'c1'),
      ]);

      expect(snapshot.toolCalls.single.status, ToolCallStatus.executing);
    });

    test('End for an unknown call is ignored', () {
      const snapshot = AgentSnapshot();

      expect(
        reduceAgentEvent(snapshot, const ToolCallEndEvent(toolCallId: 'x')),
        same(snapshot),
      );
    });

    test('Result completes the call and appends a tool message', () {
      final snapshot = _replay(const [
        _start,
        ToolCallEndEvent(toolCallId: 'c1'),
        ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'c1',
          content: '{"forecast": "sunny"}',
        ),
      ]);

      final view = snapshot.toolCalls.single;
      expect(view.status, ToolCallStatus.complete);
      expect(view.result, '{"forecast": "sunny"}');
      final message = snapshot.messages.last as ToolMessage;
      expect(message.id, 't1');
      expect(message.toolCallId, 'c1');
      expect(message.content, '{"forecast": "sunny"}');
    });

    test('Result for an unknown call still appends the tool message', () {
      final snapshot = reduceAgentEvent(
        const AgentSnapshot(),
        const ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'x',
          content: 'done',
        ),
      );

      expect(snapshot.toolCalls, isEmpty);
      expect(snapshot.messages.single, isA<ToolMessage>());
    });

    test('a repeated Result is ignored', () {
      const result = ToolCallResultEvent(
        messageId: 't1',
        toolCallId: 'c1',
        content: 'done',
      );
      final completed = _replay(const [_start, result]);

      expect(reduceAgentEvent(completed, result), same(completed));
    });

    group('chunks', () {
      test('first chunk starts the call, later chunks grow its args', () {
        final snapshot = _replay(const [
          ToolCallChunkEvent(
            toolCallId: 'c1',
            toolCallName: 'showWeather',
            parentMessageId: 'm1',
            delta: '{"city":',
          ),
          ToolCallChunkEvent(delta: ' "Lima"'),
          ToolCallChunkEvent(toolCallId: 'c1', delta: '}'),
        ]);

        final view = snapshot.toolCalls.single;
        expect(view.name, 'showWeather');
        expect(view.args, {'city': 'Lima'});
        expect(snapshot.messages.single.id, 'm1');
      });

      test('a chunk without a name for an unknown call is ignored', () {
        const snapshot = AgentSnapshot();

        expect(
          reduceAgentEvent(
            snapshot,
            const ToolCallChunkEvent(toolCallId: 'c1', delta: '{}'),
          ),
          same(snapshot),
        );
        expect(
          reduceAgentEvent(snapshot, const ToolCallChunkEvent(delta: '{}')),
          same(snapshot),
        );
      });

      test('a chunk without delta only starts the call', () {
        final snapshot = reduceAgentEvent(
          const AgentSnapshot(),
          const ToolCallChunkEvent(toolCallId: 'c1', toolCallName: 'tool'),
        );

        expect(snapshot.toolCalls.single.args, isEmpty);
      });
    });

    test('RunFinished moves calls still in progress to executing', () {
      final snapshot = _replay(const [
        _start,
        ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'done'),
        ToolCallResultEvent(messageId: 't', toolCallId: 'c2', content: 'ok'),
        RunFinishedEvent(threadId: 't', runId: 'r'),
      ]);

      expect(snapshot.toolCalls.map((v) => v.status), [
        ToolCallStatus.executing,
        ToolCallStatus.complete,
      ]);
    });

    test('frontend_tool_call fixture leaves the call executing', () {
      final snapshot = _replay(loadFixture('frontend_tool_call').events);

      final view = snapshot.toolCalls.single;
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.executing);
      expect(view.args, {'city': 'Lima'});
      expect(view.result, isNull);
    });
  });
}
