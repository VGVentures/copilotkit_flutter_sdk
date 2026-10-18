import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';
import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('agent lifecycle', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;

    setUp(() {
      harness = ToolLoopHarness();
      client = harness.client;
    });

    test('AgentOpened talks on the given thread id', () async {
      await client.handled(const AgentOpened('default', threadId: 'thread-7'));

      expect(client.state.agents['default']!.threadId, 'thread-7');
    });

    test('AgentOpened generates a thread id when none is given', () async {
      final agent = await client.openAgent('default');

      expect(agent.threadId, isNotEmpty);
    });

    test('AgentClosed removes and closes an idle agent', () async {
      final agent = await client.openAgent('default');

      await client.handled(const AgentClosed('default'));

      expect(client.state.agents, isEmpty);
      expect(agent.isClosed, isTrue);
    });

    test('AgentClosed for an unknown agent does nothing', () async {
      await client.handled(const AgentClosed('nope'));

      expect(client.state.agents, isEmpty);
    });

    test('AgentClosed stops a running turn first', () async {
      final events = StreamController<BaseEvent>();
      harness.runs.add(events.stream);
      final agent = await client.openAgent('default');
      final run = client.runAgent(agent);
      events.add(RunStartedEvent(threadId: agent.threadId, runId: 'r1'));
      await pumpEventQueue();

      await client.handled(const AgentClosed('default'));
      await run;

      expect(client.state.agents, isEmpty);
      expect(client.state.turns, isEmpty);
      expect(agent.isClosed, isTrue);
      expect(harness.errors, isEmpty);
      verify(
        () => harness.transport.stop(
          agentId: 'default',
          threadId: agent.threadId,
          runId: any(named: 'runId'),
          headers: any(named: 'headers'),
        ),
      ).called(1);
    });

    test('a run requested for a closed agent does nothing', () async {
      final agent = await client.openAgent('default');
      await client.handled(const AgentClosed('default'));

      await client.runAgent(agent);

      verifyNever(
        () => harness.transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      );
    });

    test('a closed agent can be opened again on another thread', () async {
      await client.handled(const AgentOpened('default', threadId: 'one'));
      await client.handled(const AgentClosed('default'));

      await client.handled(const AgentOpened('default', threadId: 'two'));

      expect(client.state.agents['default']!.threadId, 'two');
    });
  });
}
