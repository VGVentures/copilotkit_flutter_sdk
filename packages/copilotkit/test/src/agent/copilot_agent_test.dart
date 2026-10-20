import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';

void main() {
  group(CopilotAgent, () {
    final user = UserMessage(id: 'u1', content: 'Hi');

    test('starts idle and empty with the given ids', () {
      expect(buildAgent().state, agentState);
    });

    test('generates a thread id when none is given', () {
      final agent = CopilotAgent(agentId: 'default');

      expect(Uuid.isValidUUID(fromString: agent.state.threadId), isTrue);
    });

    test('addMessage appends the message', () {
      final agent = buildAgent()..addMessage(user);

      expect(agent.state, agentState.copyWith(messages: [user]));
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
        final agent = buildAgent()
          ..addMessage(user)
          ..setMessages(const []);

        expect(agent.state, agentState);
      });

      test('drops the tool calls no message refers to', () {
        final agent = buildAgent()
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
    });

    group('setSharedState', () {
      test('replaces the shared state', () {
        final agent = buildAgent()
          ..setSharedState(const SharedState({'old': true}))
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          agent.state,
          agentState.copyWith(
            sharedState: () => const SharedState({'count': 1}),
          ),
        );
      });

      test('clears the shared state with null', () {
        final agent = buildAgent()
          ..setSharedState(const SharedState({'old': true}))
          ..setSharedState(null);

        expect(agent.state, agentState);
      });

      test('an equal state emits nothing', () async {
        final agent = buildAgent()
          ..setSharedState(const SharedState({'count': 1}));
        final states = agent.stream.toList();

        agent.setSharedState(const SharedState({'count': 1}));
        await agent.close();

        expect(await states, isEmpty);
      });
    });

    group('patchSharedState', () {
      test('applies the operations to the shared state', () {
        final agent = buildAgent()
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
        final agent = buildAgent()
          ..patchSharedState(const [JsonPatchAdd(path: '/count', value: 1)]);

        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('keeps the state and throws when an operation fails', () {
        final agent = buildAgent()
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
    });

    test('startTurn sets isRunning and clears the last error', () {
      final agent = buildAgent()
        ..fail('boom')
        ..startTurn();

      expect(agent.state, agentState.copyWith(isRunning: true));
    });

    test('endTurn clears isRunning and keeps the rest', () {
      final agent = buildAgent()
        ..startTurn()
        ..fail('boom')
        ..endTurn();

      expect(agent.state, agentState.copyWith(error: () => 'boom'));
    });

    test('fail records the error', () {
      final agent = buildAgent()..fail('boom');

      expect(agent.state, agentState.copyWith(error: () => 'boom'));
    });

    test('apply applies the AG-UI event right away', () {
      final agent = buildAgent()
        ..apply(const TextMessageStartEvent(messageId: 'm1'));

      expect(agent.state.messages.single.id, 'm1');
    });

    test('stream emits each new state, in order', () async {
      final agent = buildAgent();
      final states = agent.stream.toList();

      agent
        ..addMessage(user)
        ..startTurn();
      await agent.close();

      expect(await states, [
        agentState.copyWith(messages: [user]),
        agentState.copyWith(messages: [user], isRunning: true),
      ]);
    });

    test('a change that changes nothing emits nothing', () async {
      final agent = buildAgent();
      final states = agent.stream.toList();

      agent
        ..apply(const StepStartedEvent(stepName: 's'))
        ..endTurn();
      await agent.close();

      expect(await states, isEmpty);
    });

    test('ignores changes once closed', () async {
      final agent = buildAgent();
      expect(agent.isClosed, isFalse);

      await agent.close();
      agent.addMessage(user);

      expect(agent.isClosed, isTrue);
      expect(agent.state, agentState);
    });

    test('applies a recorded stream in order', () async {
      final fixture = loadFixture('text_stream');
      final deltas = [
        for (final event in fixture.events)
          if (event is TextMessageContentEvent) event.delta,
      ];
      final agent = buildAgent();
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
