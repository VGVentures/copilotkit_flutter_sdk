import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$AgentStopRequested', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;
    late StreamController<BaseEvent> events;
    late bool cancelled;
    late Future<void> run;

    setUp(() async {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      cancelled = false;
      events = StreamController<BaseEvent>(onCancel: () => cancelled = true);
      transport
        ..stubRun(() => events.stream)
        ..stubStop();
      client = TestCopilotKitBloc(
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
        ..add(RunStartedEvent(threadId: agent.state.threadId, runId: 'r'))
        ..add(const TextMessageStartEvent(messageId: 'm1'))
        ..add(const TextMessageContentEvent(messageId: 'm1', delta: 'Hal'));
      await pumpEventQueue();
    }

    Future<void> stopStreaming() async {
      await client.stopAgent(agent);
      await run;
    }

    String sentRunId() {
      final input = transport.sentInputs().single;
      return input.runId;
    }

    blocTest<CopilotKitBloc, CopilotKitState>(
      'closes the stream, ends the run and keeps the partial reply',
      build: () => client,
      act: (_) async {
        await startStreaming();
        await stopStreaming();
      },
      verify: (_) {
        expect(cancelled, isTrue);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, isNull);
        expect(agent.state.messages.single.content, 'Hal');
        expect(errors, isEmpty);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'asks the runtime to stop the same run with the run headers',
      build: () => client,
      act: (_) async {
        await startStreaming();
        await stopStreaming();
      },
      verify: (_) {
        final runId = sentRunId();
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

    late List<CopilotAgentState> changes;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'applies no events after the stop',
      build: () => client,
      act: (_) async {
        await startStreaming();
        await stopStreaming();
        changes = [];
        agent.stream.listen(changes.add);

        events.add(const TextMessageContentEvent(messageId: 'm1', delta: 'lo'));
        await pumpEventQueue();
      },
      verify: (_) {
        expect(changes, isEmpty);
        expect(agent.state.messages.single.content, 'Hal');
      },
    );

    group('while the headers are being built', () {
      late Completer<Map<String, String>> headers;

      setUp(() async {
        headers = Completer();
        client = TestCopilotKitBloc(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
          headers: () => headers.future,
          onError: (error, _) => errors.add(error),
          transport: transport,
        );
        agent = await client.openAgent('default');
      });

      void verifyNoRequest() {
        transport.verifyNoRun();
      }

      blocTest<CopilotKitBloc, CopilotKitState>(
        'stop sends no request',
        build: () => client,
        act: (_) async {
          run = client.runAgent(agent);
          await pumpEventQueue();

          await client.stopAgent(agent);
          headers.complete({});
          await run;
        },
        verify: (_) {
          verifyNoRequest();
          expect(agent.state.isRunning, isFalse);
          expect(errors, isEmpty);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'close sends no request',
        build: () => client,
        act: (bloc) async {
          run = client.runAgent(agent);
          await pumpEventQueue();

          await bloc.close();
          headers.complete({});
          await run;
        },
        verify: (_) {
          verifyNoRequest();
          expect(errors, isEmpty);
        },
      );
    });

    for (final (name, end) in [
      ('fails', (StreamController<BaseEvent> e) => e.addError(Exception())),
      ('ends early', (StreamController<BaseEvent> e) => e.close()),
    ]) {
      Future<void>? stop;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'can be added from onError when the stream $name',
        setUp: () async {
          stop = null;
          client = TestCopilotKitBloc(
            runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
            onError: (_, _) => stop ??= client.stopAgent(agent),
            transport: transport,
          );
          agent = await client.openAgent('default');
        },
        build: () => client,
        act: (_) async {
          run = client.runAgent(agent);
          await pumpEventQueue();

          end(events);
          await run;
          await stop;
        },
        verify: (_) {
          expect(stop, isNotNull);
          expect(agent.state.isRunning, isFalse);
        },
      );
    }

    blocTest<CopilotKitBloc, CopilotKitState>(
      'does nothing when the agent is not running',
      build: () => client,
      act: (_) => client.stopAgent(agent),
      expect: () => const <CopilotKitState>[],
      verify: (_) => transport.verifyNoStop(),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'can be interrupted by close',
      build: () => client,
      act: (bloc) async {
        await startStreaming();

        final stop = client.stopAgent(agent);
        await bloc.close();
        await run;

        await expectLater(stop, completes);
      },
      verify: (_) => expect(agent.isClosed, isTrue),
    );

    final failure = Exception('stop failed');

    blocTest<CopilotKitBloc, CopilotKitState>(
      'reports a failed runtime stop but still stops locally',
      setUp: () => transport.stubStopThrows(failure),
      build: () => client,
      act: (_) async {
        await startStreaming();
        await stopStreaming();
      },
      verify: (_) {
        expect(agent.state.isRunning, isFalse);
        expect(errors, [same(failure)]);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'can run again after a stop',
      build: () => client,
      act: (_) async {
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

        await client.runAgent(agent);
      },
      verify: (_) {
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.messages.map((m) => m.content), ['Hal', 'Again']);
      },
    );

    late TurnState turn;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'tracks the turn and its run in the client state',
      build: () => client,
      act: (_) async {
        await startStreaming();
        turn = client.state.turns['default']!;
        expect(turn.signal.isCancelled, isFalse);
        await stopStreaming();
      },
      verify: (_) => expect(turn.signal.isCancelled, isTrue),
      expect: () => [
        isA<CopilotKitState>().having(
          (state) => state.turns['default']?.run,
          'run',
          isNull,
        ),
        isA<CopilotKitState>().having(
          (state) => state.turns['default']?.run?.headers,
          'run headers',
          {'Authorization': 'Bearer token'},
        ),
        isA<CopilotKitState>()
            .having((state) => state.turns, 'turns', isEmpty)
            .having((state) => state.agents.keys, 'agents', ['default']),
      ],
    );

    late StreamController<BaseEvent> otherEvents;
    late CopilotAgentBloc other;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'stops one agent while another keeps running',
      setUp: () async {
        otherEvents = StreamController<BaseEvent>();
        other = await client.openAgent('other');
        when(
          () => transport.run(
            agentId: 'other',
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => otherEvents.stream);
      },
      build: () => client,
      act: (_) async {
        await startStreaming();
        final otherRun = client.runAgent(other);
        await pumpEventQueue();
        expect(client.state.turns.keys, ['default', 'other']);

        await stopStreaming();

        expect(client.state.turns.keys, ['other']);
        expect(agent.state.isRunning, isFalse);
        expect(other.state.isRunning, isTrue);

        otherEvents
          ..add(RunStartedEvent(threadId: other.state.threadId, runId: 'o'))
          ..add(RunFinishedEvent(threadId: other.state.threadId, runId: 'o'));
        await otherEvents.close();
        await otherRun;
      },
      verify: (_) {
        expect(client.state.turns, isEmpty);
        expect(other.state.isRunning, isFalse);
        expect(errors, isEmpty);
      },
    );
  });
}
