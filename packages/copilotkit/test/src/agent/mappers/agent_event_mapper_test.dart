import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/mappers/agent_event_mapper.dart';
import 'package:copilotkit/src/agent/mappers/text_message_mapper.dart';
import 'package:copilotkit/src/agent/mappers/tool_call_mapper.dart';
import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';
import '../../../helpers/fixtures.dart';

class _MockTextMessageMapper extends Mock implements TextMessageMapper;

class _MockToolCallMapper extends Mock implements ToolCallMapper;

void main() {
  const agents = AgentFixtures();

  group(AgentEventMapper, () {
    group('dispatch', () {
      late _MockTextMessageMapper text;
      late _MockToolCallMapper toolCalls;
      late AgentEventMapper mapper;
      const from = AgentFixtures.state;
      final mapped = from.copyWith(isRunning: true);

      setUp(() {
        text = _MockTextMessageMapper();
        toolCalls = _MockToolCallMapper();
        mapper = AgentEventMapper(text: text, toolCalls: toolCalls);
      });

      test('sends text message events to the text mapper', () {
        when(() => text.start(from, 'm1', TextMessageRole.user, 'ada'))
            .thenReturn(mapped);
        when(() => text.append(from, 'm1', TextMessageRole.assistant, 'Hi'))
            .thenReturn(mapped);
        when(() => text.appendChunk(from, 'm1', TextMessageRole.user, 'Hi'))
            .thenReturn(mapped);
        when(() => text.appendChunk(from, null, null, '')).thenReturn(mapped);

        for (final event in [
          const TextMessageStartEvent(
            messageId: 'm1',
            role: TextMessageRole.user,
            name: 'ada',
          ),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
          const TextMessageChunkEvent(
            messageId: 'm1',
            role: TextMessageRole.user,
            delta: 'Hi',
          ),
          const TextMessageChunkEvent(),
        ]) {
          expect(mapper(from, event), mapped, reason: '$event');
        }
      });

      test('sends tool call events to the tool call mapper', () {
        const chunk = ToolCallChunkEvent(toolCallId: 'c1', delta: '{}');
        final messages = [UserMessage(id: 'u1', content: 'Hi')];
        when(() => toolCalls.start(from, 'c1', 'showWeather', 'm1'))
            .thenReturn(mapped);
        when(() => toolCalls.appendArgs(from, 'c1', '{}')).thenReturn(mapped);
        when(() => toolCalls.end(from, 'c1')).thenReturn(mapped);
        when(() => toolCalls.applyChunk(from, chunk)).thenReturn(mapped);
        when(() => toolCalls.complete(from, 't1', 'c1', 'ok'))
            .thenReturn(mapped);
        when(() => toolCalls.finishArgs(from)).thenReturn(mapped);
        when(() => toolCalls.replaceMessages(from, messages))
            .thenReturn(mapped);

        for (final event in [
          const ToolCallStartEvent(
            toolCallId: 'c1',
            toolCallName: 'showWeather',
            parentMessageId: 'm1',
          ),
          const ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
          const ToolCallEndEvent(toolCallId: 'c1'),
          chunk,
          const ToolCallResultEvent(
            messageId: 't1',
            toolCallId: 'c1',
            content: 'ok',
          ),
          const RunFinishedEvent(threadId: 't', runId: 'r'),
          MessagesSnapshotEvent(messages: messages),
        ]) {
          expect(mapper(from, event), mapped, reason: '$event');
        }
      });
    });

    group('lifecycle', () {
      final user = UserMessage(id: 'u1', content: 'Hi');

      // The client owns isRunning for the whole turn (runs plus tool
      // handlers), so lifecycle events never toggle it.
      test('RunStarted clears the previous error, not isRunning', () {
        final result = agents.map(
          [RunStartedEvent(threadId: 't', runId: 'r')],
          from: AgentFixtures.state.copyWith(
            isRunning: true,
            error: () => 'boom',
          ),
        );
        expect(result.states, [AgentFixtures.state.copyWith(isRunning: true)]);
      });

      test('RunFinished leaves isRunning to the client', () {
        final result = agents.map(const [
          RunFinishedEvent(threadId: 't', runId: 'r'),
        ], from: AgentFixtures.state.copyWith(isRunning: true));
        expect(result.states, const <CopilotKitAgentState>[]);
      });

      test('RunError keeps the error and leaves isRunning', () {
        final result = agents.map(const [
          RunErrorEvent(message: 'Bad key', code: 'AUTH'),
        ], from: AgentFixtures.state.copyWith(isRunning: true));
        expect(result.states, [
          AgentFixtures.state.copyWith(
            isRunning: true,
            error: () => const RunErrorEvent(message: 'Bad key', code: 'AUTH'),
          ),
        ]);
      });

      test('steps leave the state unchanged', () {
        final result = agents.map(const [
          StepStartedEvent(stepName: 's'),
          StepFinishedEvent(stepName: 's'),
        ], from: AgentFixtures.state.copyWith(isRunning: true));
        expect(result.states, const <CopilotKitAgentState>[]);
      });

      test('keeps messages and state across the run', () {
        final result = agents.map(
          [
            RunStartedEvent(threadId: 't', runId: 'r'),
            const RunFinishedEvent(threadId: 't', runId: 'r'),
          ],
          from: AgentFixtures.state.copyWith(
            messages: [user],
            sharedState: () => const SharedState({'a': 1}),
            error: () => 'boom',
          ),
        );
        expect(result.states, [
          AgentFixtures.state.copyWith(
            messages: [user],
            sharedState: () => const SharedState({'a': 1}),
          ),
        ]);
      });
    });

    group('shared state', () {
      test('StateSnapshot replaces the state', () {
        final result = agents.map(const [
          StateSnapshotEvent(snapshot: {'count': 1}),
          StateSnapshotEvent(snapshot: {'items': <Object?>[]}),
        ]);
        expect(result.states, [
          AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({'count': 1}),
          ),
          AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({'items': <Object?>[]}),
          ),
        ]);
      });

      final counted = AgentFixtures.state.copyWith(
        sharedState: () => const SharedState({'count': 1}),
      );

      test('a StateSnapshot of null clears the state', () {
        final result = agents.map(const [
          StateSnapshotEvent(snapshot: null),
        ], from: counted);
        expect(result.states, [AgentFixtures.state]);
      });

      test('a StateSnapshot that is not a JSON object is dropped', () {
        final result = agents.map(const [
          StateSnapshotEvent(snapshot: ['a']),
        ], from: counted);
        expect(result.states, const <CopilotKitAgentState>[]);
      });

      test('StateDelta applies a JSON Patch to the state', () {
        final result = agents.map(
          const [
            StateDeltaEvent(
              delta: [
                {'op': 'replace', 'path': '/count', 'value': 2},
                {'op': 'add', 'path': '/items/-', 'value': 'b'},
              ],
            ),
          ],
          from: AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({
              'count': 1,
              'items': ['a'],
            }),
          ),
        );
        expect(result.states, [
          AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({
              'count': 2,
              'items': ['a', 'b'],
            }),
          ),
        ]);
      });

      test('StateDelta applies to an empty object when there is no state', () {
        final result = agents.map(const [
          StateDeltaEvent(
            delta: [
              {'op': 'add', 'path': '/count', 'value': 1},
            ],
          ),
        ]);
        expect(result.states, [
          AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({'count': 1}),
          ),
        ]);
      });

      final before = AgentFixtures.state.copyWith(
        sharedState: () => const SharedState({
          'items': ['a'],
        }),
      );

      test('StateDelta does not mutate the previous state', () {
        agents.map(const [
          StateDeltaEvent(
            delta: [
              {'op': 'add', 'path': '/items/-', 'value': 'b'},
            ],
          ),
        ], from: before);
        expect(
          before.sharedState,
          const SharedState({
            'items': ['a'],
          }),
        );
      });

      test('a StateDelta that does not apply leaves the state unchanged', () {
        final result = agents.map(
          const [
            StateDeltaEvent(
              delta: [
                {'op': 'remove', 'path': '/missing'},
              ],
            ),
          ],
          from: AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({'count': 1}),
          ),
        );
        expect(result.states, const <CopilotKitAgentState>[]);
      });

      test('a StateDelta that leaves no JSON object is dropped', () {
        final result = agents.map(const [
          StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '', 'value': 'text'},
            ],
          ),
        ], from: counted);
        expect(result.states, const <CopilotKitAgentState>[]);
      });
    });

    test('unknown events leave the state unchanged', () {
      final result = agents.map(const [
        CustomEvent(name: 'progress', value: 1),
      ], from: AgentFixtures.state.copyWith(isRunning: true));
      expect(result.states, const <CopilotKitAgentState>[]);
    });

    group('recorded fixtures', () {
      test('text_stream builds one assistant message', () {
        final result = agents.map(Fixture.load('text_stream').events);
        expect(
          result.state.messages.single,
          isA<AssistantMessage>().having(
            (m) => m.content,
            'content',
            'Hello! Wonderful to meet you.',
          ),
        );
        expect(result.state.error, isNull);
      });

      test('run_error keeps the runtime error', () {
        final result = agents.map(Fixture.load('run_error').events);
        expect(result.state.messages, isEmpty);
        expect(
          result.state.error,
          isA<RunErrorEvent>().having(
            (error) => error.message,
            'message',
            contains('gemini-2.5-flash'),
          ),
        );
      });

      test('dropped_connection keeps the partial reply', () {
        final result = agents.map(Fixture.load('dropped_connection').events);
        expect(result.state.messages.single.content, 'Hello! Wonderful to');
        expect(result.state.error, isNull);
      });

      test('frontend_tool_call leaves the call executing', () {
        final result = agents.map(Fixture.load('frontend_tool_call').events);
        final view = result.state.toolCalls.single;
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.executing);
        expect(view.args, const JsonObject({'city': 'Lima'}));
        expect(view.result, isNull);
      });
    });
  });
}
