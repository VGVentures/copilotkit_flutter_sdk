import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';
import '../../../helpers/fixtures.dart';

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
  group('$CopilotAgentBloc reduces tool calls', () {
    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Start adds an in-progress view with empty args',
      build: buildAgent,
      act: (agent) => agent.receive(const [_start]),
      verify: (agent) {
        final view = agent.state.toolCalls.single;
        expect(view.id, 'c1');
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.inProgress);
        expect(view.args, isEmpty);
        expect(view.result, isNull);
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Start records the call on a new assistant message',
      build: buildAgent,
      act: (agent) => agent.receive(const [_start]),
      verify: (agent) {
        final message = agent.state.messages.single as AssistantMessage;
        expect(message.id, 'm1');
        final call = message.toolCalls!.single;
        expect(call.id, 'c1');
        expect(call.type, 'function');
        expect(call.function.name, 'showWeather');
        expect(call.function.arguments, '');
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Start without a parent message uses the call id',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
      ]),
      verify: (agent) => expect(agent.state.messages.single.id, 'c1'),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Start adds the call to an existing assistant message',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        TextMessageStartEvent(messageId: 'm1'),
        TextMessageContentEvent(messageId: 'm1', delta: 'Checking'),
        _start,
        ToolCallStartEvent(
          toolCallId: 'c2',
          toolCallName: 'other',
          parentMessageId: 'm1',
        ),
      ]),
      verify: (agent) {
        final message = agent.state.messages.single as AssistantMessage;
        expect(message.content, 'Checking');
        expect(message.toolCalls!.map((c) => c.id), ['c1', 'c2']);
        expect(agent.state.toolCalls.map((v) => v.id), ['c1', 'c2']);
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'a repeated Start is ignored',
      build: buildAgent,
      act: (agent) => agent.receive(const [_start, _start]),
      expect: () => [_hasArgs(isEmpty)],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Args grow the raw arguments and the parsed partial args',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Li'),
        ToolCallArgsEvent(toolCallId: 'c1', delta: 'ma"}'),
      ]),
      expect: () => [
        _hasArgs(isEmpty),
        _hasArgs({'city': 'Li'}),
        _hasArgs({'city': 'Lima'}),
      ],
      verify: (agent) {
        final message = agent.state.messages.single as AssistantMessage;
        expect(
          message.toolCalls!.single.function.arguments,
          '{"city": "Lima"}',
        );
      },
    );

    final user = UserMessage(id: 'u1', content: 'Weather?');

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Args leave other messages untouched',
      build: buildAgent,
      seed: () => agentState.copyWith(messages: [user]),
      act: (agent) => agent.receive(const [
        _start,
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
      ]),
      verify: (agent) => expect(agent.state.messages.first, same(user)),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Args for an unknown call are ignored',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        ToolCallArgsEvent(toolCallId: 'x', delta: '{}'),
      ]),
      expect: () => const <CopilotAgentState>[],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'End moves the call to executing',
      build: buildAgent,
      act: (agent) =>
          agent.receive(const [_start, ToolCallEndEvent(toolCallId: 'c1')]),
      verify: (agent) =>
          expect(agent.state.toolCalls.single.status, ToolCallStatus.executing),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'End for an unknown call is ignored',
      build: buildAgent,
      act: (agent) => agent.receive(const [ToolCallEndEvent(toolCallId: 'x')]),
      expect: () => const <CopilotAgentState>[],
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Result completes the call and appends a tool message',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        _start,
        ToolCallEndEvent(toolCallId: 'c1'),
        ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'c1',
          content: '{"forecast": "sunny"}',
        ),
      ]),
      verify: (agent) {
        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, '{"forecast": "sunny"}');
        final message = agent.state.messages.last as ToolMessage;
        expect(message.id, 't1');
        expect(message.toolCallId, 'c1');
        expect(message.content, '{"forecast": "sunny"}');
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'Result for an unknown call still appends the tool message',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        ToolCallResultEvent(messageId: 't1', toolCallId: 'x', content: 'done'),
      ]),
      verify: (agent) {
        expect(agent.state.toolCalls, isEmpty);
        expect(agent.state.messages.single, isA<ToolMessage>());
      },
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'a repeated Result is ignored',
      build: buildAgent,
      act: (agent) {
        const result = ToolCallResultEvent(
          messageId: 't1',
          toolCallId: 'c1',
          content: 'done',
        );
        agent.receive(const [_start, result, result]);
      },
      expect: () => hasLength(2),
    );

    group('chunks', () {
      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'first chunk starts the call, later chunks grow its args',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          ToolCallChunkEvent(
            toolCallId: 'c1',
            toolCallName: 'showWeather',
            parentMessageId: 'm1',
            delta: '{"city":',
          ),
          ToolCallChunkEvent(delta: ' "Lima"'),
          ToolCallChunkEvent(toolCallId: 'c1', delta: '}'),
        ]),
        verify: (agent) {
          final view = agent.state.toolCalls.single;
          expect(view.name, 'showWeather');
          expect(view.args, {'city': 'Lima'});
          expect(agent.state.messages.single.id, 'm1');
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk without a name for an unknown call is ignored',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          ToolCallChunkEvent(toolCallId: 'c1', delta: '{}'),
          ToolCallChunkEvent(delta: '{}'),
        ]),
        expect: () => const <CopilotAgentState>[],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a chunk without delta only starts the call',
        build: buildAgent,
        act: (agent) => agent.receive(const [
          ToolCallChunkEvent(toolCallId: 'c1', toolCallName: 'tool'),
        ]),
        expect: () => [_hasArgs(isEmpty)],
      );
    });

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'RunFinished moves calls still in progress to executing',
      build: buildAgent,
      act: (agent) => agent.receive(const [
        _start,
        ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'done'),
        ToolCallResultEvent(messageId: 't', toolCallId: 'c2', content: 'ok'),
        RunFinishedEvent(threadId: 't', runId: 'r'),
      ]),
      verify: (agent) => expect(agent.state.toolCalls.map((v) => v.status), [
        ToolCallStatus.executing,
        ToolCallStatus.complete,
      ]),
    );

    blocTest<CopilotAgentBloc, CopilotAgentState>(
      'frontend_tool_call fixture leaves the call executing',
      build: buildAgent,
      act: (agent) => agent.receive(loadFixture('frontend_tool_call').events),
      verify: (agent) {
        final view = agent.state.toolCalls.single;
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.executing);
        expect(view.args, {'city': 'Lima'});
        expect(view.result, isNull);
      },
    );

    group('MessagesSnapshot', () {
      const assistant = AssistantMessage(
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
            function: FunctionCall(name: 'showMap', arguments: '{"zoom": 3}'),
          ),
        ],
      );
      const result = ToolMessage(
        id: 't1',
        toolCallId: 'c1',
        content: '{"forecast": "sunny"}',
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'rebuilds the tool calls held by its messages',
        build: buildAgent,
        act: (agent) => agent.receive([
          MessagesSnapshotEvent(messages: [assistant, result]),
        ]),
        verify: (agent) {
          final [first, second] = agent.state.toolCalls;
          expect(first.name, 'showWeather');
          expect(first.args, {'city': 'Lima'});
          expect(first.status, ToolCallStatus.complete);
          expect(first.result, '{"forecast": "sunny"}');
          expect(second.name, 'showMap');
          expect(second.args, {'zoom': 3});
          expect(second.status, ToolCallStatus.executing);
          expect(second.result, isNull);
        },
      );

      const weatherMessage = AssistantMessage(
        id: 'm1',
        toolCalls: [
          ToolCall(
            id: 'c1',
            function: FunctionCall(name: 'showWeather', arguments: '{}'),
          ),
        ],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'keeps the view of a call it already knows',
        build: buildAgent,
        act: (agent) => agent.receive([
          _start,
          const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Li'),
          MessagesSnapshotEvent(messages: const [weatherMessage]),
        ]),
        verify: (agent) {
          final view = agent.state.toolCalls.single;
          expect(view.status, ToolCallStatus.inProgress);
          expect(view.args, {'city': 'Li'});
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'completes a known call whose result it holds',
        build: buildAgent,
        act: (agent) => agent.receive([
          _start,
          const ToolCallEndEvent(toolCallId: 'c1'),
          MessagesSnapshotEvent(
            messages: const [
              weatherMessage,
              ToolMessage(id: 't1', toolCallId: 'c1', content: 'ok'),
            ],
          ),
        ]),
        verify: (agent) {
          final view = agent.state.toolCalls.single;
          expect(view.status, ToolCallStatus.complete);
          expect(view.result, 'ok');
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'drops the calls its messages no longer hold',
        build: buildAgent,
        act: (agent) =>
            agent.receive([_start, MessagesSnapshotEvent(messages: const [])]),
        verify: (agent) => expect(agent.state.toolCalls, isEmpty),
      );
    });

    group('awaiting a response', () {
      const executing = [_start, ToolCallEndEvent(toolCallId: 'c1')];

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'AgentToolCallAwaiting marks an executing call',
        build: buildAgent,
        act: (agent) => agent
          ..receive(executing)
          ..add(const AgentToolCallAwaiting('c1')),
        verify: (agent) {
          final view = agent.state.toolCalls.single;
          expect(view.status, ToolCallStatus.executing);
          expect(view.awaitingResponse, isTrue);
          expect(agent.state.awaitingResponseIds, ['c1']);
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'AgentToolCallAwaiting ignores a call that is still streaming',
        build: buildAgent,
        act: (agent) => agent
          ..receive(const [_start])
          ..add(const AgentToolCallAwaiting('c1')),
        verify: (agent) =>
            expect(agent.state.toolCalls.single.awaitingResponse, isFalse),
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'AgentToolCallAwaiting ignores an unknown call',
        build: buildAgent,
        act: (agent) => agent.add(const AgentToolCallAwaiting('missing')),
        expect: () => const <CopilotAgentState>[],
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a result completes the call and stops it from awaiting',
        build: buildAgent,
        act: (agent) => agent
          ..receive(executing)
          ..add(const AgentToolCallAwaiting('c1'))
          ..receive(const [
            ToolCallResultEvent(
              messageId: 't1',
              toolCallId: 'c1',
              content: 'ok',
            ),
          ]),
        verify: (agent) {
          final view = agent.state.toolCalls.single;
          expect(view.status, ToolCallStatus.complete);
          expect(view.awaitingResponse, isFalse);
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a snapshot that holds the result stops the call from awaiting',
        build: buildAgent,
        act: (agent) => agent
          ..receive(executing)
          ..add(const AgentToolCallAwaiting('c1'))
          ..receive([
            MessagesSnapshotEvent(
              messages: const [
                AssistantMessage(
                  id: 'm1',
                  toolCalls: [
                    ToolCall(
                      id: 'c1',
                      function: FunctionCall(
                        name: 'showWeather',
                        arguments: '{}',
                      ),
                    ),
                  ],
                ),
                ToolMessage(id: 't1', toolCallId: 'c1', content: 'ok'),
              ],
            ),
          ]),
        verify: (agent) {
          expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
          expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
        },
      );

      blocTest<CopilotAgentBloc, CopilotAgentState>(
        'a snapshot that does not hold the result keeps the call awaiting',
        build: buildAgent,
        act: (agent) => agent
          ..receive(executing)
          ..add(const AgentToolCallAwaiting('c1'))
          ..receive([
            MessagesSnapshotEvent(
              messages: const [
                AssistantMessage(
                  id: 'm1',
                  toolCalls: [
                    ToolCall(
                      id: 'c1',
                      function: FunctionCall(
                        name: 'showWeather',
                        arguments: '{}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        verify: (agent) =>
            expect(agent.state.toolCalls.single.awaitingResponse, isTrue),
      );
    });
  });
}
