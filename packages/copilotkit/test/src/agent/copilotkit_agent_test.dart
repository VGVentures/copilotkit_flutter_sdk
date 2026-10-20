import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';

void main() {
  const agents = AgentFixtures();

  group(CopilotKitAgent, () {
    final user = UserMessage(id: 'u1', content: 'Hi');

    test('starts idle and empty with the given ids', () {
      expect(agents.build().state, AgentFixtures.state);
    });

    test('generates a thread id when none is given', () {
      final agent = CopilotKitAgent(agentId: 'default');

      expect(Uuid.isValidUUID(fromString: agent.state.threadId), isTrue);
    });

    test('addMessage appends the message', () {
      final agent = agents.build()..addMessage(user);

      expect(agent.state, AgentFixtures.state.copyWith(messages: [user]));
    });

    group('setMessages', () {
      const assistant = AssistantMessage(
        id: 'a1',
        toolCalls: [
          ToolCall(
            id: 'c1',
            function: FunctionCall(name: 'showWeather', arguments: '{}'),
          ),
        ],
      );

      test('replaces the messages', () {
        final agent = agents.build()
          ..addMessage(user)
          ..setMessages(const []);

        expect(agent.state, AgentFixtures.state);
      });

      test('drops the tool calls no message refers to', () {
        final agent = agents.build()
          ..addMessage(user)
          ..apply(
            const ToolCallStartEvent(
              toolCallId: 'c1',
              toolCallName: 'showWeather',
              parentMessageId: 'a1',
            ),
          )
          ..apply(
            const ToolCallStartEvent(
              toolCallId: 'c2',
              toolCallName: 'showWeather',
              parentMessageId: 'a2',
            ),
          )
          ..setMessages(const [assistant]);

        expect(agent.state.messages, const [assistant]);
        expect(agent.state.toolCalls.map((view) => view.id), ['c1']);
      });

      test('rebuilds the tool calls its messages hold', () {
        final agent = agents.build()..setMessages(const [assistant]);

        final view = agent.state.toolCalls.single;
        expect(view.id, 'c1');
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.executing);
      });
    });

    group('setSharedState', () {
      test('replaces the shared state', () {
        final agent = agents.build()
          ..setSharedState(const SharedState({'old': true}))
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          agent.state,
          AgentFixtures.state.copyWith(
            sharedState: () => const SharedState({'count': 1}),
          ),
        );
      });

      test('clears the shared state with null', () {
        final agent = agents.build()
          ..setSharedState(const SharedState({'old': true}))
          ..setSharedState(null);

        expect(agent.state, AgentFixtures.state);
      });

      test('an equal state emits nothing', () async {
        final agent = agents.build()
          ..setSharedState(const SharedState({'count': 1}));
        final states = agent.stream.toList();

        agent.setSharedState(const SharedState({'count': 1}));
        await agent.close();

        expect(await states, isEmpty);
      });
    });

    group('patchSharedState', () {
      test('applies the operations to the shared state', () {
        final agent = agents.build()
          ..setSharedState(
            const SharedState({
              'count': 1,
              'items': ['a'],
            }),
          )
          ..patchSharedState(const [
            JsonPatchReplace(path: '/count', value: 2),
            JsonPatchAdd(path: '/items/-', value: 'b'),
          ]);

        expect(
          agent.state.sharedState,
          const SharedState({
            'count': 2,
            'items': ['a', 'b'],
          }),
        );
      });

      test('patches a missing state as an empty object', () {
        final agent = agents.build()
          ..patchSharedState(const [JsonPatchAdd(path: '/count', value: 1)]);

        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('keeps the state and throws when an operation fails', () {
        final agent = agents.build()
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          () => agent.patchSharedState(const [
            JsonPatchReplace(path: '/count', value: 2),
            JsonPatchRemove(path: '/missing'),
          ]),
          throwsFormatException,
        );
        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('keeps the state and throws when the result is no object', () {
        final agent = agents.build()
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          () => agent.patchSharedState(const [
            JsonPatchReplace(path: '', value: 'text'),
          ]),
          throwsFormatException,
        );
        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });
    });

    group('awaitResponse', () {
      const start = ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'confirmAction',
        parentMessageId: 'a1',
      );
      const end = ToolCallEndEvent(toolCallId: 'c1');
      const assistant = AssistantMessage(
        id: 'a1',
        toolCalls: [
          ToolCall(
            id: 'c1',
            function: FunctionCall(name: 'confirmAction', arguments: '{}'),
          ),
        ],
      );

      CopilotKitAgent awaiting() => agents.build()
        ..apply(start)
        ..apply(end)
        ..awaitResponse('c1');

      test('marks an executing call', () {
        final agent = awaiting();

        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.executing);
        expect(view.awaitingResponse, isTrue);
        expect(agent.state.awaitingResponseIds, ['c1']);
      });

      test('ignores a call that is still streaming', () {
        final agent = agents.build()
          ..apply(start)
          ..awaitResponse('c1');

        expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
      });

      test('ignores an unknown call', () async {
        final agent = agents.build();
        final states = agent.stream.toList();

        agent.awaitResponse('missing');
        await agent.close();

        expect(await states, isEmpty);
      });

      test('a result completes the call and stops it from awaiting', () {
        final agent = awaiting()
          ..apply(
            const ToolCallResultEvent(
              messageId: 't1',
              toolCallId: 'c1',
              content: 'ok',
            ),
          );

        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.awaitingResponse, isFalse);
      });

      test('a snapshot that holds the result stops the call from awaiting', () {
        final agent = awaiting()
          ..setMessages(const [
            assistant,
            ToolMessage(id: 't1', toolCallId: 'c1', content: 'ok'),
          ]);

        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.awaitingResponse, isFalse);
      });

      test('a snapshot without the result keeps the call awaiting', () {
        final agent = awaiting()..setMessages(const [assistant]);

        expect(agent.state.toolCalls.single.awaitingResponse, isTrue);
      });
    });

    test('startTurn sets isRunning and clears the last error', () {
      final agent = agents.build()
        ..fail('boom')
        ..startTurn();

      expect(agent.state, AgentFixtures.state.copyWith(isRunning: true));
    });

    test('endTurn clears isRunning and keeps the rest', () {
      final agent = agents.build()
        ..startTurn()
        ..fail('boom')
        ..endTurn();

      expect(agent.state, AgentFixtures.state.copyWith(error: () => 'boom'));
    });

    test('fail records the error', () {
      final agent = agents.build()..fail('boom');

      expect(agent.state, AgentFixtures.state.copyWith(error: () => 'boom'));
    });

    test('apply applies the AG-UI event right away', () {
      final agent = agents.build()
        ..apply(const TextMessageStartEvent(messageId: 'm1'));

      expect(agent.state.messages.single.id, 'm1');
    });

    test('stream emits each new state, in order', () async {
      final agent = agents.build();
      final states = agent.stream.toList();

      agent
        ..addMessage(user)
        ..startTurn();
      await agent.close();

      expect(await states, [
        AgentFixtures.state.copyWith(messages: [user]),
        AgentFixtures.state.copyWith(messages: [user], isRunning: true),
      ]);
    });

    test('a change that changes nothing emits nothing', () async {
      final agent = agents.build();
      final states = agent.stream.toList();

      agent
        ..apply(const StepStartedEvent(stepName: 's'))
        ..endTurn();
      await agent.close();

      expect(await states, isEmpty);
    });

    test('ignores changes once closed', () async {
      final agent = agents.build();
      expect(agent.isClosed, isFalse);

      await agent.close();
      agent.addMessage(user);

      expect(agent.isClosed, isTrue);
      expect(agent.state, AgentFixtures.state);
    });

    test('applies a recorded stream in order', () async {
      final fixture = Fixture.load('text_stream');
      final deltas = [
        for (final event in fixture.events)
          if (event is TextMessageContentEvent) event.delta,
      ];
      final agent = agents.build();
      final states = agent.stream.toList();

      fixture.events.forEach(agent.apply);
      await agent.close();

      expect(
        [for (final state in await states) state.messages.single.content],
        [for (var i = 0; i <= deltas.length; i++) deltas.take(i).join()],
      );
    });
  });
}
