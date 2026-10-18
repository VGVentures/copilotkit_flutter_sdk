import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/copilot_agent_event.dart';
import 'package:copilotkit/src/agent/models/agent_state.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';

import '../../helpers/agent_reducer.dart';
import '../../helpers/fixtures.dart';

const _start = ToolCallStartEvent(
  toolCallId: 'c1',
  toolCallName: 'showWeather',
  parentMessageId: 'm1',
);

void main() {
  group('CopilotAgent reduces tool calls', () {
    test('Start adds an in-progress view with empty args', () async {
      final snapshot = await reduce(const AgentState(), _start);

      final view = snapshot.toolCalls.single;
      expect(view.id, 'c1');
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.inProgress);
      expect(view.args, isEmpty);
      expect(view.result, isNull);
    });

    test('Start records the call on a new assistant message', () async {
      final snapshot = await reduce(const AgentState(), _start);

      final message = snapshot.messages.single as AssistantMessage;
      expect(message.id, 'm1');
      final call = message.toolCalls!.single;
      expect(call.id, 'c1');
      expect(call.type, 'function');
      expect(call.function.name, 'showWeather');
      expect(call.function.arguments, '');
    });

    test('Start without a parent message uses the call id', () async {
      final snapshot = await reduce(
        const AgentState(),
        const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
      );

      expect(snapshot.messages.single.id, 'c1');
    });

    test('Start adds the call to an existing assistant message', () async {
      final snapshot = await replay(const [
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

    test('a repeated Start is ignored', () async {
      final started = await reduce(const AgentState(), _start);

      expect(await reduce(started, _start), same(started));
    });

    test('Args grow the raw arguments and the parsed partial args', () async {
      final started = await reduce(const AgentState(), _start);
      final partial = await reduce(
        started,
        const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Li'),
      );
      final complete = await reduce(
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

    test('Args leave other messages untouched', () async {
      final user = UserMessage(id: 'u1', content: 'Weather?');

      final snapshot = await replay(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
      ], AgentState(messages: [user]));

      expect(snapshot.messages.first, same(user));
    });

    test('Args for an unknown call are ignored', () async {
      const snapshot = AgentState();

      expect(
        await reduce(
          snapshot,
          const ToolCallArgsEvent(toolCallId: 'x', delta: '{}'),
        ),
        same(snapshot),
      );
    });

    test('End moves the call to executing', () async {
      final snapshot = await replay(const [
        _start,
        ToolCallEndEvent(toolCallId: 'c1'),
      ]);

      expect(snapshot.toolCalls.single.status, ToolCallStatus.executing);
    });

    test('End for an unknown call is ignored', () async {
      const snapshot = AgentState();

      expect(
        await reduce(snapshot, const ToolCallEndEvent(toolCallId: 'x')),
        same(snapshot),
      );
    });

    test('Result completes the call and appends a tool message', () async {
      final snapshot = await replay(const [
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

    group('AgentToolCallClosed', () {
      Future<AgentState> close(ToolCallStatus status) =>
          replay([_start, const ToolCallEndEvent(toolCallId: 'c1')])
              .then((state) async {
                final agent = testAgent()
                  ..emit(state)
                  ..add(
                    AgentToolCallClosed(
                      toolCallId: 'c1',
                      messageId: 't1',
                      content: 'nope',
                      status: status,
                    ),
                  );
                await agent.settled;
                return agent.state;
              });

      for (final status in [ToolCallStatus.failed, ToolCallStatus.cancelled]) {
        test(
          'ends the call as $status with the message as its result',
          () async {
            final state = await close(status);

            expect(state.toolCalls.single.status, status);
            expect(state.toolCalls.single.result, 'nope');
            expect((state.messages.last as ToolMessage).content, 'nope');
          },
        );
      }
    });

    test('Result for an unknown call still appends the tool message', () async {
      final snapshot = await reduce(
        const AgentState(),
        const ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'x',
          content: 'done',
        ),
      );

      expect(snapshot.toolCalls, isEmpty);
      expect(snapshot.messages.single, isA<ToolMessage>());
    });

    test('a repeated Result is ignored', () async {
      const result = ToolCallResultEvent(
        messageId: 't1',
        toolCallId: 'c1',
        content: 'done',
      );
      final completed = await replay(const [_start, result]);

      expect(await reduce(completed, result), same(completed));
    });

    group('chunks', () {
      test('first chunk starts the call, later chunks grow its args', () async {
        final snapshot = await replay(const [
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

      test('a chunk without a name for an unknown call is ignored', () async {
        const snapshot = AgentState();

        expect(
          await reduce(
            snapshot,
            const ToolCallChunkEvent(toolCallId: 'c1', delta: '{}'),
          ),
          same(snapshot),
        );
        expect(
          await reduce(snapshot, const ToolCallChunkEvent(delta: '{}')),
          same(snapshot),
        );
      });

      test('a chunk without delta only starts the call', () async {
        final snapshot = await reduce(
          const AgentState(),
          const ToolCallChunkEvent(toolCallId: 'c1', toolCallName: 'tool'),
        );

        expect(snapshot.toolCalls.single.args, isEmpty);
      });
    });

    test('RunFinished moves calls still in progress to executing', () async {
      final snapshot = await replay(const [
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

    test('frontend_tool_call fixture leaves the call executing', () async {
      final snapshot = await replay(loadFixture('frontend_tool_call').events);

      final view = snapshot.toolCalls.single;
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.executing);
      expect(view.args, {'city': 'Lima'});
      expect(view.result, isNull);
    });
  });
}
