import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/mock_agent_transport.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient stopAgent', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late StreamController<BaseEvent> events;
    late bool cancelled;
    late Future<void> run;

    CopilotKitClient buildClient({
      HeadersBuilder? headers,
      CopilotErrorHandler? onError,
    }) => CopilotKitClient(
      runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
      headers: headers ?? () async => {'Authorization': 'Bearer token'},
      onError: onError ?? (error, _) => errors.add(error),
      transport: transport,
    );

    setUp(() {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      cancelled = false;
      events = StreamController<BaseEvent>(onCancel: () => cancelled = true);
      transport
        ..stubRun(() => events.stream)
        ..stubStop();
      client = buildClient();
      agent = client.agent('default');
    });

    Future<void> startStreaming() async {
      run = client.runAgent('default');
      events
        ..add(RunStartedEvent(threadId: agent.state.threadId, runId: 'r'))
        ..add(const TextMessageStartEvent(messageId: 'm1'))
        ..add(const TextMessageContentEvent(messageId: 'm1', delta: 'Hal'));
      await pumpEventQueue();
    }

    Future<void> stopStreaming() async {
      await client.stopAgent('default');
      await run;
    }

    test(
      'closes the stream, ends the run and keeps the partial reply',
      () async {
        await startStreaming();
        await stopStreaming();

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
        await stopStreaming();

        final runId = transport.sentInputs().single.runId;
        verify(
          () => transport.stop(
            agentId: 'default',
            threadId: agent.state.threadId,
            runId: runId,
            headers: {'Authorization': 'Bearer token'},
          ),
        ).called(1);
      },
    );

    test('applies no events after the stop', () async {
      await startStreaming();
      await stopStreaming();
      final changes = <CopilotAgentState>[];
      agent.stream.listen(changes.add);

      events.add(const TextMessageContentEvent(messageId: 'm1', delta: 'lo'));
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(agent.state.messages.single.content, 'Hal');
    });

    group('while the headers are being built', () {
      late Completer<Map<String, String>> headers;

      setUp(() {
        headers = Completer();
        client = buildClient(headers: () => headers.future);
        agent = client.agent('default');
      });

      test('stop sends no request', () async {
        run = client.runAgent('default');
        await pumpEventQueue();

        await client.stopAgent('default');
        headers.complete({});
        await run;

        transport.verifyNoRun();
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      test('close sends no request', () async {
        run = client.runAgent('default');
        await pumpEventQueue();

        await client.close();
        headers.complete({});
        await run;

        transport.verifyNoRun();
        expect(errors, isEmpty);
      });
    });

    for (final (name, end) in [
      ('fails', (StreamController<BaseEvent> e) => e.addError(Exception())),
      ('ends early', (StreamController<BaseEvent> e) => e.close()),
    ]) {
      test('can be called from onError when the stream $name', () async {
        Future<void>? stop;
        client = buildClient(
          onError: (_, _) => stop ??= client.stopAgent('default'),
        );
        agent = client.agent('default');

        run = client.runAgent('default');
        await pumpEventQueue();
        end(events);
        await run;
        await stop;

        expect(stop, isNotNull);
        expect(agent.state.isRunning, isFalse);
      });
    }

    test('does nothing when the agent is not running', () async {
      await client.stopAgent('default');

      expect(agent.state.isRunning, isFalse);
      transport.verifyNoStop();
    });

    test('does nothing for an agent that was never opened', () async {
      await client.stopAgent('missing');

      expect(client.agents.keys, ['default']);
      transport.verifyNoStop();
    });

    test('can be interrupted by close', () async {
      await startStreaming();

      final stop = client.stopAgent('default');
      await client.close();
      await run;

      await expectLater(stop, completes);
      expect(agent.isClosed, isTrue);
    });

    final failure = Exception('stop failed');

    test('reports a failed runtime stop but still stops locally', () async {
      transport.stubStopThrows(failure);

      await startStreaming();
      await stopStreaming();

      expect(agent.state.isRunning, isFalse);
      expect(errors, [same(failure)]);
    });

    test('can run again after a stop', () async {
      await startStreaming();
      await stopStreaming();
      transport.stubRun(
        () => Stream.fromIterable([
          RunStartedEvent(threadId: agent.state.threadId, runId: 'r2'),
          const TextMessageStartEvent(messageId: 'm2'),
          const TextMessageContentEvent(messageId: 'm2', delta: 'Again'),
          RunFinishedEvent(threadId: agent.state.threadId, runId: 'r2'),
        ]),
      );

      await client.runAgent('default');

      expect(agent.state.isRunning, isFalse);
      expect(agent.state.messages.map((m) => m.content), ['Hal', 'Again']);
    });

    test('stops one agent while another keeps running', () async {
      final otherEvents = StreamController<BaseEvent>();
      final other = client.agent('other');
      when(
        () => transport.run(
          agentId: 'other',
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => otherEvents.stream);

      await startStreaming();
      final otherRun = client.runAgent('other');
      await pumpEventQueue();
      expect(agent.state.isRunning, isTrue);
      expect(other.state.isRunning, isTrue);

      await stopStreaming();

      expect(agent.state.isRunning, isFalse);
      expect(other.state.isRunning, isTrue);

      otherEvents
        ..add(RunStartedEvent(threadId: other.state.threadId, runId: 'o'))
        ..add(RunFinishedEvent(threadId: other.state.threadId, runId: 'o'));
      await otherEvents.close();
      await otherRun;

      expect(other.state.isRunning, isFalse);
      expect(errors, isEmpty);
    });
  });
}
