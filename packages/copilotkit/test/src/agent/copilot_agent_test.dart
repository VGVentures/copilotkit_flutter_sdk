import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/agent/copilot_agent_event.dart';
import 'package:test/test.dart';

import '../../helpers/agent_reducer.dart';
import '../../helpers/fixtures.dart';

void main() {
  group(CopilotAgent, () {
    final user = UserMessage(id: 'u1', content: 'Hi');

    blocTest<CopilotAgent, AgentState>(
      'AgentMessageAdded appends the message',
      build: testAgent,
      act: (agent) => agent.add(AgentMessageAdded(user)),
      expect: () => [
        AgentState(messages: [user]),
      ],
    );

    blocTest<CopilotAgent, AgentState>(
      'AgentTurnStarted sets isRunning and clears the last error',
      build: testAgent,
      seed: () => const AgentState(error: 'boom'),
      act: (agent) => agent.add(const AgentTurnStarted()),
      expect: () => const [AgentState(isRunning: true)],
    );

    blocTest<CopilotAgent, AgentState>(
      'AgentTurnEnded clears isRunning and keeps the rest',
      build: testAgent,
      seed: () => const AgentState(isRunning: true, error: 'boom'),
      act: (agent) => agent.add(const AgentTurnEnded()),
      expect: () => const [AgentState(error: 'boom')],
    );

    blocTest<CopilotAgent, AgentState>(
      'AgentRunFailed records the error',
      build: testAgent,
      seed: () => const AgentState(isRunning: true),
      act: (agent) => agent.add(const AgentRunFailed('boom')),
      expect: () => const [AgentState(isRunning: true, error: 'boom')],
    );

    blocTest<CopilotAgent, AgentState>(
      'AgentEventReceived applies the AG-UI event',
      build: testAgent,
      act: (agent) => agent.add(
        const AgentEventReceived(TextMessageStartEvent(messageId: 'm1')),
      ),
      expect: () => [
        isA<AgentState>().having(
          (s) => s.messages.single.id,
          'message id',
          'm1',
        ),
      ],
    );

    blocTest<CopilotAgent, AgentState>(
      'an event that changes nothing emits nothing',
      build: testAgent,
      act: (agent) =>
          agent.add(const AgentEventReceived(StepStartedEvent(stepName: 's'))),
      expect: () => const <AgentState>[],
    );

    test('settled completes once every added event is applied', () async {
      final agent = testAgent();
      await expectLater(agent.settled, completes);

      agent
        ..add(AgentMessageAdded(user))
        ..add(const AgentTurnStarted());
      expect(agent.state.messages, isEmpty);

      await agent.settled;

      expect(agent.state.messages, [user]);
      expect(agent.state.isRunning, isTrue);
      await agent.close();
    });

    test('applies a recorded stream in order', () async {
      final fixture = loadFixture('text_stream');
      final deltas = [
        for (final event in fixture.events)
          if (event is TextMessageContentEvent) event.delta,
      ];
      final seen = <String>[];
      final agent = testAgent();
      agent.stream.listen((state) {
        final last = state.messages.lastOrNull;
        if (last is AssistantMessage) seen.add(last.content ?? '');
      });

      for (final event in fixture.events) {
        agent.add(AgentEventReceived(event));
      }
      await agent.settled;

      final text = (agent.state.messages.single as AssistantMessage).content;
      expect(text, deltas.join());
      expect(seen, [
        for (var i = 0; i <= deltas.length; i++) deltas.take(i).join(),
      ]);
      await agent.close();
    });
  });

  group(CopilotAgentEvent, () {
    test('supports value equality', () {
      final user = UserMessage(id: 'u1', content: 'Hi');
      final event = RunStartedEvent(threadId: 't', runId: 'r');

      expect(AgentEventReceived(event), AgentEventReceived(event));
      expect(AgentMessageAdded(user), AgentMessageAdded(user));
      // Non-const instances, so equality goes through props.
      // ignore: prefer_const_constructors
      expect(AgentTurnStarted(), AgentTurnStarted());
      // Same reason as above.
      // ignore: prefer_const_constructors
      expect(AgentTurnEnded(), AgentTurnEnded());
      expect(const AgentRunFailed('boom'), const AgentRunFailed('boom'));
      expect(const AgentRunFailed('boom'), isNot(const AgentRunFailed('x')));
      const closed = AgentToolCallClosed(
        toolCallId: 'c1',
        messageId: 't1',
        content: 'x',
        status: ToolCallStatus.failed,
      );
      expect(closed, closed);
      expect(
        closed,
        isNot(
          const AgentToolCallClosed(
            toolCallId: 'c1',
            messageId: 't1',
            content: 'x',
            status: ToolCallStatus.cancelled,
          ),
        ),
      );
    });
  });
}
