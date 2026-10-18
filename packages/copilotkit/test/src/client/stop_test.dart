import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';

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

    setUp(() async {
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
      agent = await client.openAgent('default');
    });

    Future<void> startStreaming() async {
      run = client.runAgent(agent);
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

        await client.stopAgent(agent);
        await run;

        expect(cancelled, isTrue);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, isNull);
        expect(agent.state.messages.single.content, 'Hal');
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
      await client.stopAgent(agent);
      await run;
      final changes = <AgentState>[];
      agent.stream.listen(changes.add);

      events.add(const TextMessageContentEvent(messageId: 'm1', delta: 'lo'));
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(agent.state.messages.single.content, 'Hal');
    });

    group('while the headers are being built', () {
      late Completer<Map<String, String>> headers;

      setUp(() async {
        headers = Completer();
        client = CopilotKitClient(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
          headers: () => headers.future,
          onError: (error, _) => errors.add(error),
          transport: transport,
        );
        agent = await client.openAgent('default');
      });

      void verifyNoRequest() {
        verifyNever(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        );
      }

      test('stop sends no request', () async {
        run = client.runAgent(agent);
        await pumpEventQueue();

        await client.stopAgent(agent);
        headers.complete({});
        await run;

        verifyNoRequest();
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      test('dispose sends no request', () async {
        when(() => transport.close()).thenAnswer((_) async {});
        run = client.runAgent(agent);
        await pumpEventQueue();

        await client.close();
        headers.complete({});
        await run;

        verifyNoRequest();
        expect(errors, isEmpty);
      });
    });

    for (final (name, end) in [
      ('fails', (StreamController<BaseEvent> e) => e.addError(Exception())),
      ('ends early', (StreamController<BaseEvent> e) => e.close()),
    ]) {
      test('can be called from onError when the stream $name', () async {
        Future<void>? stop;
        client = CopilotKitClient(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
          onError: (_, _) => stop ??= client.stopAgent(agent),
          transport: transport,
        );
        agent = await client.openAgent('default');
        run = client.runAgent(agent);
        await pumpEventQueue();

        end(events);
        await run;

        expect(stop, isNotNull);
        await expectLater(stop, completes);
        expect(agent.state.isRunning, isFalse);
      });
    }

    test('does nothing when the agent is not running', () async {
      await client.stopAgent(agent);

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

      await expectLater(client.stopAgent(agent), completes);
      await run;

      expect(agent.state.isRunning, isFalse);
      expect(errors, [same(failure)]);
    });

    test('can run again after a stop', () async {
      await startStreaming();
      await client.stopAgent(agent);
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

      await client.runAgent(agent);

      expect(agent.state.isRunning, isFalse);
      expect(agent.state.messages.map((m) => m.content), ['Hal', 'Again']);
    });

    test('tracks the turn and its run in the client state', () async {
      expect(client.state.turns, isEmpty);

      await startStreaming();

      final turn = client.state.turns[agent.agentId]!;
      expect(turn.controller.isCancelled, isFalse);
      expect(turn.run?.headers, {'Authorization': 'Bearer token'});

      await client.stopAgent(agent);
      await run;

      expect(client.state.turns, isEmpty);
      expect(turn.controller.isCancelled, isTrue);
    });

    test('stops one agent while another keeps running', () async {
      final otherEvents = StreamController<BaseEvent>();
      final other = await client.openAgent('other');
      when(
        () => transport.run(
          agentId: 'other',
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => otherEvents.stream);
      await startStreaming();
      final otherRun = client.runAgent(other);
      await pumpEventQueue();
      expect(client.state.turns.keys, ['default', 'other']);

      await client.stopAgent(agent);
      await run;

      expect(client.state.turns.keys, ['other']);
      expect(agent.state.isRunning, isFalse);
      expect(other.state.isRunning, isTrue);

      otherEvents
        ..add(RunStartedEvent(threadId: other.threadId, runId: 'o'))
        ..add(RunFinishedEvent(threadId: other.threadId, runId: 'o'));
      await otherEvents.close();
      await otherRun;

      expect(client.state.turns, isEmpty);
      expect(other.state.isRunning, isFalse);
      expect(errors, isEmpty);
    });
  });
}
