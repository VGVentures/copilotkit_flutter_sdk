import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  });

  group('stopAgent', () {
    late _MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late StreamController<BaseEvent> events;
    late bool cancelled;
    late Future<void> run;

    setUp(() {
      transport = _MockAgentTransport();
      errors = [];
      cancelled = false;
      events = StreamController<BaseEvent>(onCancel: () => cancelled = true);
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => events.stream);
      when(
        () => transport.stop(
          agentId: any(named: 'agentId'),
          threadId: any(named: 'threadId'),
          runId: any(named: 'runId'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {});
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        headers: () async => {'Authorization': 'Bearer token'},
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
      agent = client.agent('default');
    });

    Future<void> startStreaming() async {
      run = agent.run();
      events
        ..add(RunStartedEvent(threadId: agent.threadId, runId: 'r'))
        ..add(const TextMessageStartEvent(messageId: 'm1'))
        ..add(const TextMessageContentEvent(messageId: 'm1', delta: 'Hal'));
      await pumpEventQueue();
    }

    String sentRunId() {
      final input =
          verify(
                () => transport.run(
                  agentId: any(named: 'agentId'),
                  input: captureAny(named: 'input'),
                  headers: any(named: 'headers'),
                ),
              ).captured.single
              as RunAgentInput;
      return input.runId;
    }

    test(
      'closes the stream, ends the run and keeps the partial reply',
      () async {
        await startStreaming();

        await agent.stop();
        await run;

        expect(cancelled, isTrue);
        expect(agent.isRunning, isFalse);
        expect(agent.snapshot.error, isNull);
        expect(agent.messages.single.content, 'Hal');
        expect(errors, isEmpty);
      },
    );

    test(
      'asks the runtime to stop the same run with the run headers',
      () async {
        await startStreaming();

        await client.stopAgent(agent);
        await run;

        final runId = sentRunId();
        verify(
          () => transport.stop(
            agentId: 'default',
            threadId: agent.threadId,
            runId: runId,
            headers: {'Authorization': 'Bearer token'},
          ),
        ).called(1);
      },
    );

    test('applies no events after the stop', () async {
      await startStreaming();
      await agent.stop();
      await run;
      final changes = <AgentSnapshot>[];
      agent.changes.listen(changes.add);

      events.add(const TextMessageContentEvent(messageId: 'm1', delta: 'lo'));
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(agent.messages.single.content, 'Hal');
    });

    test('does nothing when the agent is not running', () async {
      await agent.stop();

      verifyNever(
        () => transport.stop(
          agentId: any(named: 'agentId'),
          threadId: any(named: 'threadId'),
          runId: any(named: 'runId'),
          headers: any(named: 'headers'),
        ),
      );
    });

    test('reports a failed runtime stop but still stops locally', () async {
      final failure = Exception('stop failed');
      when(
        () => transport.stop(
          agentId: any(named: 'agentId'),
          threadId: any(named: 'threadId'),
          runId: any(named: 'runId'),
          headers: any(named: 'headers'),
        ),
      ).thenThrow(failure);
      await startStreaming();

      await expectLater(agent.stop(), completes);
      await run;

      expect(agent.isRunning, isFalse);
      expect(errors, [same(failure)]);
    });

    test('can run again after a stop', () async {
      await startStreaming();
      await agent.stop();
      await run;
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          RunStartedEvent(threadId: agent.threadId, runId: 'r2'),
          const TextMessageStartEvent(messageId: 'm2'),
          const TextMessageContentEvent(messageId: 'm2', delta: 'Again'),
          RunFinishedEvent(threadId: agent.threadId, runId: 'r2'),
        ]),
      );

      await agent.run();

      expect(agent.isRunning, isFalse);
      expect(agent.messages.map((m) => m.content), ['Hal', 'Again']);
    });
  });
}
