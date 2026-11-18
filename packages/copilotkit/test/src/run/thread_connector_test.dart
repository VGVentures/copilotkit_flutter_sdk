import 'dart:async';

import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/run/run.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/messages.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/runner_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(ThreadConnector, () {
    late RunnerHarness harness;
    late MockAgentTransport transport;
    late CopilotAgent agent;
    late List<Object> errors;
    late Turn turn;

    void useHarness(RunnerHarness next) {
      harness = next;
      transport = next.transport;
      agent = next.agent;
      errors = next.errors;
      turn = Turn(agent);
    }

    setUp(() => useHarness(RunnerHarness()));

    Future<void> connect() => harness.connector(turn);

    void queueReplay(List<ag_ui.BaseEvent> events) =>
        harness.connects.add(Stream.fromIterable(events));

    test(
      'sends the thread with an empty conversation and the headers',
      () async {
        useHarness(
          RunnerHarness(headers: () async => {'Authorization': 'Bearer token'}),
        );
        agent.addMessage(const UserMessage(id: 'u1', content: 'Hi'));

        await connect();

        final input =
            verify(
                  () => transport.connect(
                    agentId: 'default',
                    input: captureAny(named: 'input'),
                    headers: {'Authorization': 'Bearer token'},
                  ),
                ).captured.single
                as ag_ui.RunAgentInput;
        expect(input.threadId, agent.state.threadId);
        expect(Uuid.isValidUUID(fromString: input.runId), isTrue);
        expect(input.messages, isEmpty);
        expect(input.state, <String, Object?>{});
        expect(input.tools, isEmpty);
        expect(input.context, isEmpty);
        expect(input.forwardedProps, isNull);
      },
    );

    test('rebuilds the conversation from the replayed history', () async {
      queueReplay(loadFixture('connect_replay').events);

      await connect();

      expect(agent.state.messages.map(textOf), [
        'Say hello in five words.',
        'Hello there, have a great day!',
        'And goodbye?',
        'Goodbye, have a wonderful day!',
      ]);
      expect(agent.state.messages.map((m) => m.id), [
        'user-1',
        '0539b5c2-f173-4da2-8fc9-07ad54abb072',
        'user-2',
        '160ac371-2d2c-4f0b-9df7-e5cadce93e57',
      ]);
      expect(agent.state.error, isNull);
      expect(errors, isEmpty);
    });

    test('starts from an empty conversation and shared state', () async {
      agent
        ..addMessage(const UserMessage(id: 'old', content: 'Old'))
        ..setSharedState(const SharedState({'count': 1}));
      queueReplay(loadFixture('connect_replay').events);

      await connect();

      expect(agent.state.messages.map((m) => m.id), isNot(contains('old')));
      expect(agent.state.sharedState, isNull);
    });

    test('restores the shared state the history ends with', () async {
      queueReplay([
        ag_ui.RunStartedEvent(threadId: 't', runId: 'r'),
        const ag_ui.StateSnapshotEvent(snapshot: {'count': 2}),
        const ag_ui.RunFinishedEvent(threadId: 't', runId: 'r'),
      ]);

      await connect();

      expect(agent.state.sharedState, const SharedState({'count': 2}));
    });

    test('leaves the agent empty when there is no history', () async {
      final before = agent.state;

      await connect();

      expect(agent.state, before);
      expect(errors, isEmpty);
    });

    test('stays connected while a run of the thread is still going', () async {
      final events = StreamController<ag_ui.BaseEvent>();
      harness.connects.add(events.stream);
      final done = connect();
      events
        ..add(ag_ui.RunStartedEvent(threadId: 't', runId: 'r'))
        ..add(const ag_ui.TextMessageStartEvent(messageId: 'a1'))
        ..add(
          const ag_ui.TextMessageContentEvent(messageId: 'a1', delta: 'He'),
        );
      await pumpEventQueue();

      expect(turn.run, isNotNull);
      expect(agent.state.messages.map(textOf), ['He']);

      events
        ..add(const ag_ui.TextMessageContentEvent(messageId: 'a1', delta: 'y'))
        ..add(const ag_ui.RunFinishedEvent(threadId: 't', runId: 'r'));
      await events.close();
      await done;

      expect(agent.state.messages.map(textOf), ['Hey']);
      expect(turn.run, isNull);
      expect(errors, isEmpty);
    });

    test('does not add the messages of a run twice', () async {
      agent.addMessage(const UserMessage(id: 'u1', content: 'Hi'));
      queueReplay([
        ag_ui.RunStartedEvent(
          threadId: 't',
          runId: 'r',
          input: ag_ui.RunAgentInput(
            threadId: 't',
            runId: 'r',
            messages: [ag_ui.UserMessage(id: 'u1', content: 'Hi')],
            tools: const [],
            context: const [],
          ),
        ),
        const ag_ui.RunFinishedEvent(threadId: 't', runId: 'r'),
      ]);

      await connect();

      // The conversation was reset first, so the one copy is the replayed one.
      expect(agent.state.messages.map((m) => m.id), ['u1']);
    });

    test('records a replayed run error without reporting it', () async {
      queueReplay([
        ag_ui.RunStartedEvent(threadId: 't', runId: 'r'),
        const ag_ui.RunErrorEvent(message: 'Rate limited', code: '429'),
      ]);

      await connect();

      expect(
        agent.state.error,
        const RunError(message: 'Rate limited', code: '429'),
      );
      expect(errors, isEmpty);
    });

    test('reports a connection that fails', () async {
      final failure = StateError('runtime down');
      harness.connects.add(Stream.error(failure));

      await connect();

      expect(agent.state.error, same(failure));
      expect(errors, [same(failure)]);
      expect(turn.run, isNull);
    });

    test('accepts a replay that ends without the end of its run', () async {
      queueReplay([
        ag_ui.RunStartedEvent(threadId: 't', runId: 'r'),
        const ag_ui.TextMessageStartEvent(messageId: 'a1'),
      ]);

      await connect();

      expect(agent.state.error, isNull);
      expect(errors, isEmpty);
    });

    test('reports a transport that throws', () async {
      final failure = StateError('closed');
      when(
        () => transport.connect(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
        ),
      ).thenThrow(failure);

      await connect();

      expect(agent.state.error, same(failure));
      expect(errors, [same(failure)]);
      expect(turn.run, isNull);
    });

    test('reports a headers builder that throws', () async {
      final failure = StateError('no token');
      useHarness(RunnerHarness(headers: () async => throw failure));

      await connect();

      expect(agent.state.error, same(failure));
      expect(errors, [same(failure)]);
      transport.verifyNoConnect();
    });

    test('connects nothing when stopped while building the headers', () async {
      final headers = Completer<Map<String, String>>();
      useHarness(RunnerHarness(headers: () => headers.future));
      agent.addMessage(const UserMessage(id: 'u1', content: 'Hi'));

      final done = connect();
      turn.signal.cancel();
      headers.complete({});
      await done;

      transport.verifyNoConnect();
      expect(agent.state.messages, hasLength(1));
    });

    test('ends when the turn is stopped, leaving the run to cancel', () async {
      final events = StreamController<ag_ui.BaseEvent>();
      harness.connects.add(events.stream);
      final done = connect();
      events.add(ag_ui.RunStartedEvent(threadId: 't', runId: 'r'));
      await pumpEventQueue();

      turn.signal.cancel();
      await done;

      expect(turn.run, isNotNull);
      expect(turn.run!.runId, isNull);
      await turn.run!.subscription.cancel();
    });
  });
}
