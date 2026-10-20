import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/mappers/tool_call_mapper.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';

void main() {
  group(ToolCallMapper, () {
    const mapper = ToolCallMapper();
    const state = AgentFixtures.state;
    final started = mapper.start(state, 'c1', 'showWeather', 'm1');
    final user = UserMessage(id: 'u1', content: 'Weather?');

    group('start', () {
      test('adds an in-progress view with empty args', () {
        final view = started.toolCalls.single;

        expect(view.id, 'c1');
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.inProgress);
        expect(view.args, const JsonObject());
        expect(view.result, isNull);
      });

      test('records the call on a new assistant message', () {
        final message = started.messages.single as AssistantMessage;
        expect(message.id, 'm1');
        final call = message.toolCalls!.single;
        expect(call.id, 'c1');
        expect(call.type, 'function');
        expect(call.function.name, 'showWeather');
        expect(call.function.arguments, '');
      });

      test('without a parent message uses the call id', () {
        final next = mapper.start(state, 'c1', 'tool', null);

        expect(next.messages.single.id, 'c1');
      });

      test('adds the call to the parent assistant message', () {
        final from = state.copyWith(
          messages: [const AssistantMessage(id: 'm1', content: 'Checking')],
        );

        final next = mapper.start(
          mapper.start(from, 'c1', 'showWeather', 'm1'),
          'c2',
          'other',
          'm1',
        );

        final message = next.messages.single as AssistantMessage;
        expect(message.content, 'Checking');
        expect(message.toolCalls!.map((c) => c.id), ['c1', 'c2']);
        expect(next.toolCalls.map((v) => v.id), ['c1', 'c2']);
      });

      test('ignores a call that already exists', () {
        expect(mapper.start(started, 'c1', 'showWeather', 'm1'), started);
      });
    });

    group('appendArgs', () {
      test('grows the raw arguments and the parsed partial args', () {
        final partial = mapper.appendArgs(started, 'c1', '{"city": "Li');
        final complete = mapper.appendArgs(partial, 'c1', 'ma"}');

        expect(partial.toolCalls.single.args, const JsonObject({'city': 'Li'}));
        expect(
          complete.toolCalls.single.args,
          const JsonObject({'city': 'Lima'}),
        );
        final message = complete.messages.single as AssistantMessage;
        expect(
          message.toolCalls!.single.function.arguments,
          '{"city": "Lima"}',
        );
      });

      test('leaves other messages untouched', () {
        final from = mapper.start(
          state.copyWith(messages: [user]),
          'c1',
          'showWeather',
          'm1',
        );

        final next = mapper.appendArgs(from, 'c1', '{}');

        expect(next.messages.first, user);
      });

      test('ignores an unknown call', () {
        expect(mapper.appendArgs(state, 'x', '{}'), state);
      });
    });

    group('end', () {
      test('moves the call to executing', () {
        expect(
          mapper.end(started, 'c1').toolCalls.single.status,
          ToolCallStatus.executing,
        );
      });

      test('ignores an unknown call', () {
        expect(mapper.end(state, 'x'), state);
      });
    });

    group('applyChunk', () {
      test('the first chunk starts the call, later chunks grow its args', () {
        final next = [
          const ToolCallChunkEvent(
            toolCallId: 'c1',
            toolCallName: 'showWeather',
            parentMessageId: 'm1',
            delta: '{"city":',
          ),
          const ToolCallChunkEvent(delta: ' "Lima"'),
          const ToolCallChunkEvent(toolCallId: 'c1', delta: '}'),
        ].fold(state, mapper.applyChunk);

        final view = next.toolCalls.single;
        expect(view.name, 'showWeather');
        expect(view.args, const JsonObject({'city': 'Lima'}));
        expect(next.messages.single.id, 'm1');
      });

      test('a chunk without a name for an unknown call is ignored', () {
        expect(
          mapper.applyChunk(
            state,
            const ToolCallChunkEvent(toolCallId: 'c1', delta: '{}'),
          ),
          state,
        );
      });

      test('a chunk without an id and no prior call is ignored', () {
        expect(
          mapper.applyChunk(state, const ToolCallChunkEvent(delta: '{}')),
          state,
        );
      });

      test('a chunk without delta only starts the call', () {
        final next = mapper.applyChunk(
          state,
          const ToolCallChunkEvent(toolCallId: 'c1', toolCallName: 'tool'),
        );

        expect(next.toolCalls.single.args, const JsonObject());
      });
    });

    group('complete', () {
      test('completes the call and appends a tool message', () {
        final next = mapper.complete(
          mapper.end(started, 'c1'),
          't1',
          'c1',
          '{"forecast": "sunny"}',
        );

        final view = next.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, '{"forecast": "sunny"}');
        final message = next.messages.last as ToolMessage;
        expect(message.id, 't1');
        expect(message.toolCallId, 'c1');
        expect(message.content, '{"forecast": "sunny"}');
      });

      test('for an unknown call still appends the tool message', () {
        final next = mapper.complete(state, 't1', 'x', 'done');

        expect(next.toolCalls, isEmpty);
        expect(next.messages.single, isA<ToolMessage>());
      });

      test('ignores a tool message that already exists', () {
        final completed = mapper.complete(started, 't1', 'c1', 'done');

        expect(mapper.complete(completed, 't1', 'c1', 'done'), completed);
      });
    });

    group('finishArgs', () {
      test('moves the calls still in progress to executing', () {
        final next = mapper.finishArgs(
          mapper.complete(
            mapper.start(started, 'c2', 'done', null),
            't',
            'c2',
            'ok',
          ),
        );

        expect(next.toolCalls.map((v) => v.status), [
          ToolCallStatus.executing,
          ToolCallStatus.complete,
        ]);
      });

      test('leaves a state without calls in progress unchanged', () {
        final executing = mapper.end(started, 'c1');

        expect(mapper.finishArgs(executing), executing);
      });
    });

    group('replaceMessages', () {
      const weatherMessage = AssistantMessage(
        id: 'm1',
        toolCalls: [
          ToolCall(
            id: 'c1',
            function: FunctionCall(name: 'showWeather', arguments: '{}'),
          ),
        ],
      );

      test('rebuilds the tool calls held by the messages', () {
        final next = mapper.replaceMessages(state, const [
          AssistantMessage(
            id: 'a1',
            toolCalls: [
              ToolCall(
                id: 'c1',
                function: FunctionCall(
                  name: 'showWeather',
                  arguments: '{"city": "Lima"}',
                ),
              ),
              ToolCall(
                id: 'c2',
                function: FunctionCall(
                  name: 'showMap',
                  arguments: '{"zoom": 3}',
                ),
              ),
            ],
          ),
          ToolMessage(
            id: 't1',
            toolCallId: 'c1',
            content: '{"forecast": "sunny"}',
          ),
        ]);

        final [first, second] = next.toolCalls;
        expect(first.name, 'showWeather');
        expect(first.args, const JsonObject({'city': 'Lima'}));
        expect(first.status, ToolCallStatus.complete);
        expect(first.result, '{"forecast": "sunny"}');
        expect(second.name, 'showMap');
        expect(second.args, const JsonObject({'zoom': 3}));
        expect(second.status, ToolCallStatus.executing);
        expect(second.result, isNull);
      });

      test('keeps the view of a call it already knows', () {
        final streaming = mapper.appendArgs(started, 'c1', '{"city": "Li');

        final next = mapper.replaceMessages(streaming, const [weatherMessage]);

        final view = next.toolCalls.single;
        expect(view.status, ToolCallStatus.inProgress);
        expect(view.args, const JsonObject({'city': 'Li'}));
      });

      test('completes a known call whose result it holds', () {
        final next = mapper.replaceMessages(mapper.end(started, 'c1'), const [
          weatherMessage,
          ToolMessage(id: 't1', toolCallId: 'c1', content: 'ok'),
        ]);

        final view = next.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, 'ok');
      });

      test('drops the calls its messages no longer hold', () {
        final next = mapper.replaceMessages(started, const []);

        expect(next.messages, isEmpty);
        expect(next.toolCalls, isEmpty);
      });
    });
  });
}
