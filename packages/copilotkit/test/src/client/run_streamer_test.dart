import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/messages.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/runner_harness.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(RunStreamer, () {
    late RunnerHarness harness;
    late MockAgentTransport transport;
    late CopilotAgent agent;
    late List<Stream<ag_ui.BaseEvent>> runs;
    late List<Object> errors;
    late Turn turn;

    void useHarness(RunnerHarness next) {
      harness = next;
      transport = next.transport;
      agent = next.agent;
      runs = next.runs;
      errors = next.errors;
      turn = Turn(agent);
    }

    setUp(() => useHarness(RunnerHarness()));

    String threadId() => agent.state.threadId;

    void queueRun(List<ag_ui.BaseEvent> events) =>
        runs.add(Stream.fromIterable(events));

    Future<RunResult> stream() => harness.streamer(turn);

    test('sends the agent, tools, context, properties and headers', () async {
      useHarness(
        RunnerHarness(
          headers: () async => {'Authorization': 'Bearer token'},
          properties: const {'userId': '42'},
        ),
      );
      harness.tools.register(weatherTool((_, {required signal}) async => ''));
      harness.context.add(
        AgentContextEntry(description: 'Unread', value: const {'count': 3}),
      );
      const message = UserMessage(id: 'u1', content: 'Hi');
      agent.addMessage(message);
      runs.add(const Stream.empty());

      await stream();

      final input =
          verify(
                () => transport.run(
                  agentId: 'default',
                  input: captureAny(named: 'input'),
                  headers: {'Authorization': 'Bearer token'},
                ),
              ).captured.single
              as ag_ui.RunAgentInput;
      expect(input.threadId, threadId());
      expect(Uuid.isValidUUID(fromString: input.runId), isTrue);
      expect(input.messages.map(Message.fromAgUi), [message]);
      expect(input.tools.single.name, 'showWeather');
      expect(input.context.single.value, '{"count":3}');
      expect(input.forwardedProps, {'userId': '42'});
    });

    test('sends the state and messages the agent has when it starts', () async {
      runs.add(const Stream.empty());

      agent
        ..setSharedState(const SharedState({'count': 3}))
        ..patchSharedState(const [StatePatchReplace(path: '/count', value: 4)])
        ..addMessage(const UserMessage(id: 'old', content: 'Old'))
        ..setMessages([const UserMessage(id: 'new', content: 'New')]);
      await stream();

      final input = transport.sentInputs().single;
      expect(input.state, {'count': 4});
      expect(input.messages.map((message) => message.id), ['new']);
    });

    test('uses a new run id for every run', () async {
      runs.addAll([const Stream.empty(), const Stream.empty()]);

      await stream();
      await stream();

      final runIds = transport.sentInputs().map((input) => input.runId);
      expect(runIds.toSet(), hasLength(2));
    });

    test('sends no headers when no builder is given', () async {
      runs.add(const Stream.empty());

      await stream();

      verify(
        () => transport.run(
          agentId: 'default',
          input: any(named: 'input'),
        ),
      ).called(1);
    });

    test('streams the assistant reply into messages', () async {
      queueRun([
        ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r'),
        const ag_ui.TextMessageStartEvent(messageId: 'm1'),
        const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
        const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
        ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'),
      ]);
      final texts = <String?>[];
      agent.stream.listen((s) => texts.add(textOf(s.messages.lastOrNull)));

      final result = await stream();
      await pumpEventQueue();

      expect(result, RunResult.finished);
      expect(textOf(agent.state.messages.single), 'Hello');
      expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
      expect(errors, isEmpty);
    });

    test('holds the run on the turn while it streams', () async {
      final events = StreamController<ag_ui.BaseEvent>();
      runs.add(events.stream);

      final result = stream();
      await pumpEventQueue();
      final run = turn.run;
      events.add(ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'));
      await events.close();
      await result;

      expect(run!.runId, transport.sentInputs().single.runId);
      expect(run.headers, isEmpty);
      expect(turn.run, isNull);
    });

    test('applies state snapshots and deltas to sharedState', () async {
      queueRun([
        ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r'),
        const ag_ui.StateSnapshotEvent(snapshot: {'count': 1}),
        const ag_ui.TextMessageStartEvent(messageId: 'm1'),
        const ag_ui.StateDeltaEvent(
          delta: [
            {'op': 'replace', 'path': '/count', 'value': 2},
          ],
        ),
        ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'),
      ]);
      final sharedStates = <Object?>[];
      agent.stream
          .map((state) => state.sharedState)
          .where((shared) => shared != null)
          .distinct()
          .listen(sharedStates.add);

      await stream();
      await pumpEventQueue();

      expect(agent.state.sharedState, const SharedState({'count': 2}));
      expect(sharedStates, [
        const SharedState({'count': 1}),
        const SharedState({'count': 2}),
      ]);
    });

    test('applies the recorded state_snapshot_delta patch', () async {
      queueRun(loadFixture('state_snapshot_delta').events);

      await stream();

      expect(
        agent.state.sharedState,
        const SharedState({
          'todos': ['buy milk', 'walk dog'],
        }),
      );
    });

    test('the state the runtime sends replaces a local edit', () async {
      queueRun([
        ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r1'),
        const ag_ui.StateSnapshotEvent(snapshot: {'count': 1}),
        ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r1'),
      ]);

      agent.setSharedState(const SharedState({'count': 3}));
      await stream();

      expect(transport.sentInputs().single.state, {'count': 3});
      expect(agent.state.sharedState, const SharedState({'count': 1}));
    });

    group('fails', () {
      final failure = Exception('connection refused');

      test('on transport errors', () async {
        runs.add(Stream.error(failure));

        expect(await stream(), RunResult.failed);
        expect(errors.single, same(failure));
        expect(agent.state.error, same(failure));
      });

      final badTransport = StateError('bad transport');

      test('on a transport that throws synchronously', () async {
        transport.stubRunThrows(badTransport);

        expect(await stream(), RunResult.failed);
        expect(errors.single, same(badTransport));
      });

      test('on a stream that ends before the run finishes', () async {
        queueRun([ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r')]);

        expect(await stream(), RunResult.failed);
        expect(errors.single, isA<StateError>());
        expect(agent.state.error, isA<StateError>());
      });

      final noToken = Exception('no token');

      test('on header builder errors, without running', () async {
        useHarness(RunnerHarness(headers: () async => throw noToken));

        expect(await stream(), RunResult.failed);
        expect(errors.single, same(noToken));
        transport.verifyNoRun();
      });

      test('on a context value that is not JSON, without running', () async {
        harness.context.add(
          AgentContextEntry(
            description: 'Clock',
            value: {'clock': DateTime(2026)},
          ),
        );

        expect(await stream(), RunResult.failed);
        expect(errors.single, isA<JsonUnsupportedObjectError>());
        transport.verifyNoRun();
      });
    });

    group('stops', () {
      test('when cancelled while the headers are being built', () async {
        final headers = Completer<Map<String, String>>();
        useHarness(RunnerHarness(headers: () => headers.future));

        final result = stream();
        await pumpEventQueue();
        turn.signal.cancel();
        headers.complete({});

        expect(await result, RunResult.stopped);
        transport.verifyNoRun();
        expect(errors, isEmpty);
      });

      test('when cancelled while the run streams', () async {
        runs.add(StreamController<ag_ui.BaseEvent>().stream);

        final result = stream();
        await pumpEventQueue();
        turn.signal.cancel();

        expect(await result, RunResult.stopped);
        expect(turn.run, isNotNull);
      });
    });

    group('resilience', () {
      test(
        'reasoning, activity, raw and custom events leave text intact',
        () async {
          queueRun([
            ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r'),
            const ag_ui.ReasoningStartEvent(messageId: 'think'),
            const ag_ui.ReasoningMessageContentEvent(
              messageId: 'think',
              delta: 'Hmm',
            ),
            const ag_ui.TextMessageStartEvent(messageId: 'm1'),
            const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
            const ag_ui.ActivitySnapshotEvent(
              messageId: 'act',
              activityType: 'search',
              content: {'query': 'weather'},
            ),
            const ag_ui.ThinkingStartEvent(title: 'plan'),
            const ag_ui.RawEvent(event: {'anything': true}),
            const ag_ui.CustomEvent(name: 'progress', value: 0.5),
            const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
            ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'),
          ]);

          expect(await stream(), RunResult.finished);
          expect(textOf(agent.state.messages.single), 'Hello');
          expect(errors, isEmpty);
        },
      );

      const runError = ag_ui.RunErrorEvent(
        message: 'Invalid API key',
        code: 'AUTH',
      );

      test('RUN_ERROR fails the run and reports the error once', () async {
        queueRun([
          ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r'),
          const ag_ui.TextMessageStartEvent(messageId: 'm1'),
          const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'Par'),
          runError,
        ]);

        expect(await stream(), RunResult.failed);
        const error = RunError(message: 'Invalid API key', code: 'AUTH');
        expect(errors, [error]);
        expect(agent.state.error, error);
        expect(textOf(agent.state.messages.single), 'Par');
      });

      test('unknown_events fixture keeps the text reply', () async {
        queueRun(loadFixture('unknown_events').events);

        expect(await stream(), RunResult.finished);
        expect(
          textOf(agent.state.messages.single),
          'Hello! Wonderful to meet you.',
        );
        expect(errors, isEmpty);
      });

      test('recorded run_error fixture reports the runtime error', () async {
        queueRun(loadFixture('run_error').events);

        expect(await stream(), RunResult.failed);
        expect(errors.single, isA<RunError>());
        expect(errors.single, agent.state.error);
        expect(
          agent.state.error,
          isA<RunError>().having(
            (error) => error.message,
            'message',
            contains('gemini-2.5-flash'),
          ),
        );
      });

      test(
        'dropped_connection fixture fails the run and keeps the partial reply',
        () async {
          queueRun(loadFixture('dropped_connection').events);

          expect(await stream(), RunResult.failed);
          expect(errors.single, isA<StateError>());
          expect(textOf(agent.state.messages.single), 'Hello! Wonderful to');
        },
      );
    });
  });
}
