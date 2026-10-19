import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
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
