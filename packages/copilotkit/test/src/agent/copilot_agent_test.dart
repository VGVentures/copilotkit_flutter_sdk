import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/messages.dart';

void main() {
  group(CopilotAgent, () {
    const user = UserMessage(id: 'u1', content: 'Hi');

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
        toolCalls: [ToolCall(id: 'c1', name: 'showWeather', arguments: '{}')],
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
            const ag_ui.ToolCallStartEvent(
              toolCallId: 'c1',
              toolCallName: 'showWeather',
              parentMessageId: 'a1',
            ),
          )
          ..apply(
            const ag_ui.ToolCallStartEvent(
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
        final agent = buildAgent()..setMessages(const [assistant]);

        final view = agent.state.toolCalls.single;
        expect(view.id, 'c1');
        expect(view.name, 'showWeather');
        expect(view.status, ToolCallStatus.executing);
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

      test('keeps an unmodifiable copy of the state', () {
        final json = <String, Object?>{'count': 1};
        final agent = buildAgent()..setSharedState(SharedState(json));
        json['count'] = 2;

        final state = agent.state.sharedState!;
        expect(state, const SharedState({'count': 1}));
        expect(() => state.toJson()['count'] = 3, throwsUnsupportedError);
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
            StatePatchReplace(path: '/count', value: 2),
            StatePatchAdd(path: '/items/-', value: 'b'),
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
          ..patchSharedState(const [StatePatchAdd(path: '/count', value: 1)]);

        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('keeps an unmodifiable state', () {
        final agent = buildAgent()
          ..patchSharedState(const [StatePatchAdd(path: '/count', value: 1)]);

        expect(
          () => agent.state.sharedState!.toJson()['count'] = 2,
          throwsUnsupportedError,
        );
      });

      test('keeps the state and throws when an operation fails', () {
        final agent = buildAgent()
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          () => agent.patchSharedState(const [
            StatePatchReplace(path: '/count', value: 2),
            StatePatchRemove(path: '/missing'),
          ]),
          throwsFormatException,
        );
        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('keeps the state and throws when the result is not an object', () {
        final agent = buildAgent()
          ..setSharedState(const SharedState({'count': 1}));

        expect(
          () => agent.patchSharedState(const [
            StatePatchReplace(path: '', value: 'text'),
          ]),
          throwsFormatException,
        );
        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });
    });

    group('awaitResponse', () {
      const start = ag_ui.ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'confirmAction',
        parentMessageId: 'a1',
      );
      const end = ag_ui.ToolCallEndEvent(toolCallId: 'c1');
      const assistant = AssistantMessage(
        id: 'a1',
        toolCalls: [ToolCall(id: 'c1', name: 'confirmAction', arguments: '{}')],
      );

      CopilotAgent awaiting() => buildAgent()
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
        final agent = buildAgent()
          ..apply(start)
          ..awaitResponse('c1');

        expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
      });

      test('ignores an unknown call', () async {
        final agent = buildAgent();
        final states = agent.stream.toList();

        agent.awaitResponse('missing');
        await agent.close();

        expect(await states, isEmpty);
      });

      test('a result completes the call and stops it from awaiting', () {
        final agent = awaiting()
          ..apply(
            const ag_ui.ToolCallResultEvent(
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
        ..apply(const ag_ui.TextMessageStartEvent(messageId: 'm1'));

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
        ..apply(const ag_ui.StepStartedEvent(stepName: 's'))
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
          if (event is ag_ui.TextMessageContentEvent) event.delta,
      ];
      final agent = buildAgent();
      final states = agent.stream.toList();

      fixture.events.forEach(agent.apply);
      await agent.close();

      // An empty delta leaves an equal state, which isn't emitted.
      expect(
        [for (final state in await states) textOf(state.messages.single)],
        {for (var i = 0; i <= deltas.length; i++) deltas.take(i).join()}
            .toList(),
      );
    });
  });
}
