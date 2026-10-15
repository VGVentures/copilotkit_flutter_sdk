import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

final Uri _runtimeUrl = Uri.parse('http://runtime.test/api/copilotkit');

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: <Context>[],
      ),
    );
  });

  group(CopilotKitClient, () {
    late _MockAgentTransport transport;
    late List<(Object, StackTrace)> errors;
    late CopilotKitClient client;

    setUp(() {
      transport = _MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: _runtimeUrl,
        headers: () async => {'Authorization': 'Bearer token'},
        properties: {'userId': '42'},
        onError: (error, stackTrace) => errors.add((error, stackTrace)),
        transport: transport,
      );
    });

    void stubRun(Stream<BaseEvent> events) {
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => events);
    }

    test('exposes its configuration', () {
      expect(client.runtimeUrl, _runtimeUrl);
      expect(client.properties, {'userId': '42'});
      expect(client.headers, isNotNull);
      expect(client.onError, isNotNull);
    });

    test('creates a default transport when none is given', () async {
      final defaultClient = CopilotKitClient(runtimeUrl: _runtimeUrl);

      await expectLater(defaultClient.dispose(), completes);
    });

    group('agent', () {
      test('returns the same agent for the same id', () {
        final agent = client.agent('default');

        expect(client.agent('default'), same(agent));
        expect(agent.agentId, 'default');
      });

      test('gives each agent its own thread', () {
        final a = client.agent('a');
        final b = client.agent('b');

        expect(Uuid.isValidUUID(fromString: a.threadId), isTrue);
        expect(a.threadId, isNot(b.threadId));
      });
    });

    group('runAgent', () {
      test('sends messages, state, properties and headers', () async {
        stubRun(const Stream.empty());
        final agent = client.agent('default');
        final message = UserMessage(id: 'u1', content: 'Hi');
        await agent.addMessage(message);

        await client.runAgent(agent);

        final input =
            verify(
                  () => transport.run(
                    agentId: 'default',
                    input: captureAny(named: 'input'),
                    headers: {'Authorization': 'Bearer token'},
                  ),
                ).captured.single
                as RunAgentInput;
        expect(input.threadId, agent.threadId);
        expect(Uuid.isValidUUID(fromString: input.runId), isTrue);
        expect(input.messages, [message]);
        expect(input.tools, isEmpty);
        expect(input.context, isEmpty);
        expect(input.forwardedProps, {'userId': '42'});
      });

      test('uses a new run id for every run', () async {
        stubRun(const Stream.empty());
        final agent = client.agent('default');

        await client.runAgent(agent);
        await client.runAgent(agent);

        final runIds = verify(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: captureAny(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).captured.cast<RunAgentInput>().map((input) => input.runId);
        expect(runIds.toSet(), hasLength(2));
      });

      test('sends no headers when no builder is given', () async {
        client = CopilotKitClient(
          runtimeUrl: _runtimeUrl,
          transport: transport,
        );
        stubRun(const Stream.empty());

        await client.runAgent(client.agent('default'));

        verify(
          () => transport.run(
            agentId: 'default',
            input: any(named: 'input'),
          ),
        ).called(1);
      });

      test('streams the assistant reply into messages', () async {
        final agent = client.agent('default');
        stubRun(
          Stream.fromIterable([
            RunStartedEvent(threadId: agent.threadId, runId: 'r'),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
            RunFinishedEvent(threadId: agent.threadId, runId: 'r'),
          ]),
        );
        final texts = <String?>[];
        agent.changes.listen((s) => texts.add(s.messages.lastOrNull?.content));

        await agent.run();
        await pumpEventQueue();

        expect(agent.messages.single.content, 'Hello');
        expect(agent.isRunning, isFalse);
        expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
        expect(errors, isEmpty);
      });

      test('emits every runtime event on events', () async {
        final agent = client.agent('default');
        final started = RunStartedEvent(threadId: agent.threadId, runId: 'r');
        final finished = RunFinishedEvent(threadId: agent.threadId, runId: 'r');
        stubRun(Stream.fromIterable([started, finished]));
        final events = <BaseEvent>[];
        agent.events.listen(events.add);

        await agent.run();
        await pumpEventQueue();

        expect(events, [same(started), same(finished)]);
      });

      test('is running as soon as the run starts', () async {
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        final agent = client.agent('default');

        final run = client.runAgent(agent);
        await pumpEventQueue();
        expect(agent.isRunning, isTrue);

        events.add(RunFinishedEvent(threadId: agent.threadId, runId: 'r'));
        await events.close();
        await run;
        expect(agent.isRunning, isFalse);
      });

      test('ignores a run while one is in progress', () async {
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        final agent = client.agent('default');
        final first = client.runAgent(agent);
        await pumpEventQueue();

        await client.runAgent(agent);

        verify(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).called(1);
        events.add(RunFinishedEvent(threadId: agent.threadId, runId: 'r'));
        await events.close();
        await first;
      });

      test('reports transport errors and ends the run', () async {
        final failure = Exception('connection refused');
        stubRun(Stream.error(failure));
        final agent = client.agent('default');

        await expectLater(client.runAgent(agent), completes);

        expect(errors.single.$1, same(failure));
        expect(agent.isRunning, isFalse);
        expect(agent.snapshot.error, same(failure));
      });

      test('reports a transport that throws synchronously', () async {
        final failure = StateError('bad transport');
        when(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenThrow(failure);
        final agent = client.agent('default');

        await expectLater(client.runAgent(agent), completes);

        expect(errors.single.$1, same(failure));
        expect(agent.isRunning, isFalse);
      });

      test('reports a stream that ends before the run finishes', () async {
        final agent = client.agent('default');
        stubRun(
          Stream.value(RunStartedEvent(threadId: agent.threadId, runId: 'r')),
        );

        await client.runAgent(agent);

        expect(errors.single.$1, isA<StateError>());
        expect(agent.isRunning, isFalse);
        expect(agent.snapshot.error, isA<StateError>());
      });

      test('reports header builder errors without running', () async {
        final failure = Exception('no token');
        client = CopilotKitClient(
          runtimeUrl: _runtimeUrl,
          headers: () async => throw failure,
          onError: (error, stackTrace) => errors.add((error, stackTrace)),
          transport: transport,
        );
        final agent = client.agent('default');

        await client.runAgent(agent);

        expect(errors.single.$1, same(failure));
        expect(agent.isRunning, isFalse);
        verifyNever(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        );
      });

      test('does not throw without an onError handler', () async {
        client = CopilotKitClient(
          runtimeUrl: _runtimeUrl,
          transport: transport,
        );
        stubRun(Stream.error(Exception('boom')));

        await expectLater(client.runAgent(client.agent('default')), completes);
      });
    });

    group('dispose', () {
      test('closes the transport and the agent streams', () async {
        final agent = client.agent('default');
        final changesDone = agent.changes.drain<void>();
        final eventsDone = agent.events.drain<void>();

        await client.dispose();

        verify(() => transport.close()).called(1);
        await expectLater(changesDone, completes);
        await expectLater(eventsDone, completes);
      });

      test('cancels active runs', () async {
        var cancelled = false;
        final events = StreamController<BaseEvent>(
          onCancel: () => cancelled = true,
        );
        stubRun(events.stream);
        final agent = client.agent('default');
        final run = client.runAgent(agent);
        await pumpEventQueue();

        await client.dispose();
        await run;

        expect(cancelled, isTrue);
      });
    });
  });

  group(CopilotAgent, () {
    late CopilotKitClient client;

    setUp(() {
      client = CopilotKitClient(
        runtimeUrl: _runtimeUrl,
        transport: _MockAgentTransport(),
      );
    });

    test('starts idle and empty', () {
      final agent = client.agent('default');

      expect(agent.messages, isEmpty);
      expect(agent.state, isNull);
      expect(agent.isRunning, isFalse);
      expect(agent.toolCalls, isEmpty);
      expect(agent.snapshot.error, isNull);
    });

    test('uses the given thread id', () {
      final agent = CopilotAgent(
        agentId: 'default',
        client: client,
        threadId: 'thread-1',
      );

      expect(agent.threadId, 'thread-1');
    });

    test('addMessage appends the message and emits a change', () async {
      final agent = client.agent('default');
      final message = UserMessage(id: 'u1', content: 'Hi');
      final change = agent.changes.first;

      await agent.addMessage(message);

      expect(agent.messages, [message]);
      expect((await change).messages, [message]);
    });

    test('stateStream does not emit when only messages change', () async {
      final agent = client.agent('default');
      final states = <Object?>[];
      agent.stateStream.listen(states.add);

      await agent.addMessage(UserMessage(id: 'u1', content: 'Hi'));
      await agent.addMessage(UserMessage(id: 'u2', content: 'Again'));
      await pumpEventQueue();

      expect(states, isEmpty);
    });
  });
}
