import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_x.dart';

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

    setUp(() async {
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

    test('exposes its configuration', () async {
      expect(client.runtimeUrl, _runtimeUrl);
      expect(client.properties, {'userId': '42'});
      expect(client.headers, isNotNull);
      expect(client.state, const CopilotKitState());
    });

    test('creates a default transport when none is given', () async {
      final defaultClient = CopilotKitClient(runtimeUrl: _runtimeUrl);

      await expectLater(defaultClient.close(), completes);
    });

    group('agent', () {
      test('returns the same agent for the same id', () async {
        final agent = await client.openAgent('default');

        expect(await client.openAgent('default'), same(agent));
        expect(agent.agentId, 'default');
      });

      test('gives each agent its own thread', () async {
        final a = await client.openAgent('a');
        final b = await client.openAgent('b');

        expect(Uuid.isValidUUID(fromString: a.threadId), isTrue);
        expect(a.threadId, isNot(b.threadId));
      });
    });

    group('runAgent', () {
      test('sends messages, state, properties and headers', () async {
        stubRun(const Stream.empty());
        final agent = await client.openAgent('default');
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
        final agent = await client.openAgent('default');

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

        await client.runAgent(await client.openAgent('default'));

        verify(
          () => transport.run(
            agentId: 'default',
            input: any(named: 'input'),
          ),
        ).called(1);
      });

      test('streams the assistant reply into messages', () async {
        final agent = await client.openAgent('default');
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
        agent.stream.listen((s) => texts.add(s.messages.lastOrNull?.content));

        await client.runAgent(agent);
        await pumpEventQueue();

        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
        expect(errors, isEmpty);
      });

      test('run and stop add the client events', () async {
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        when(
          () => transport.stop(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
            runId: any(named: 'runId'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async {});
        final agent = await client.openAgent('default');

        agent.run();
        await agent.stream.firstWhere((state) => state.isRunning);
        agent.stop();
        await agent.stream.firstWhere((state) => !state.isRunning);

        expect(agent.state.isRunning, isFalse);
        await events.close();
      });

      test('is running as soon as the run starts', () async {
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        final agent = await client.openAgent('default');

        final run = client.runAgent(agent);
        await pumpEventQueue();
        expect(agent.state.isRunning, isTrue);

        events.add(RunFinishedEvent(threadId: agent.threadId, runId: 'r'));
        await events.close();
        await run;
        expect(agent.state.isRunning, isFalse);
      });

      test('ignores a run while one is in progress', () async {
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        final agent = await client.openAgent('default');
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
        final agent = await client.openAgent('default');

        await expectLater(client.runAgent(agent), completes);

        expect(errors.single.$1, same(failure));
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, same(failure));
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
        final agent = await client.openAgent('default');

        await expectLater(client.runAgent(agent), completes);

        expect(errors.single.$1, same(failure));
        expect(agent.state.isRunning, isFalse);
      });

      test('reports a stream that ends before the run finishes', () async {
        final agent = await client.openAgent('default');
        stubRun(
          Stream.value(RunStartedEvent(threadId: agent.threadId, runId: 'r')),
        );

        await client.runAgent(agent);

        expect(errors.single.$1, isA<StateError>());
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, isA<StateError>());
      });

      test('reports header builder errors without running', () async {
        final failure = Exception('no token');
        client = CopilotKitClient(
          runtimeUrl: _runtimeUrl,
          headers: () async => throw failure,
          onError: (error, stackTrace) => errors.add((error, stackTrace)),
          transport: transport,
        );
        final agent = await client.openAgent('default');

        await client.runAgent(agent);

        expect(errors.single.$1, same(failure));
        expect(agent.state.isRunning, isFalse);
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

        await expectLater(
          client.runAgent(await client.openAgent('default')),
          completes,
        );
      });
    });

    group('dispose', () {
      test('closes the transport and the agent streams', () async {
        final agent = await client.openAgent('default');
        final changesDone = agent.stream.drain<void>();

        await client.close();

        verify(() => transport.close()).called(1);
        await expectLater(changesDone, completes);
        expect(agent.isClosed, isTrue);
      });

      test('cancels active runs', () async {
        var cancelled = false;
        final events = StreamController<BaseEvent>(
          onCancel: () => cancelled = true,
        );
        stubRun(events.stream);
        final agent = await client.openAgent('default');
        final run = client.runAgent(agent);
        await pumpEventQueue();

        await client.close();
        await run;

        expect(cancelled, isTrue);
      });
    });
  });

  group(CopilotAgent, () {
    late CopilotKitClient client;

    setUp(() async {
      client = CopilotKitClient(
        runtimeUrl: _runtimeUrl,
        transport: _MockAgentTransport(),
      );
    });

    test('starts idle and empty', () async {
      final agent = await client.openAgent('default');

      expect(agent.state.messages, isEmpty);
      expect(agent.state.sharedState, isNull);
      expect(agent.state.isRunning, isFalse);
      expect(agent.state.toolCalls, isEmpty);
      expect(agent.state.error, isNull);
    });

    test('uses the given thread id', () async {
      final agent = CopilotAgent(
        agentId: 'default',
        client: client,
        threadId: 'thread-1',
      );

      expect(agent.threadId, 'thread-1');
    });

    test('addMessage appends the message and emits a change', () async {
      final agent = await client.openAgent('default');
      final message = UserMessage(id: 'u1', content: 'Hi');
      final change = agent.stream.first;

      await agent.addMessage(message);

      expect(agent.state.messages, [message]);
      expect((await change).messages, [message]);
    });
  });
}
