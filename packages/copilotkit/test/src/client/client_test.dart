import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_x.dart';
import '../../helpers/mock_agent_transport.dart';

class _ErrorObserver extends BlocObserver {
  final List<(BlocBase<Object?>, Object)> errors = [];

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    errors.add((bloc, error));
  }
}

final Uri _runtimeUrl = Uri.parse('http://runtime.test/api/copilotkit');

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(CopilotKitClient, () {
    late MockAgentTransport transport;
    late List<(Object, StackTrace)> errors;
    late CopilotKitClient client;

    setUp(() async {
      transport = MockAgentTransport();
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
      transport.stubRun(() => events);
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

    group('state', () {
      final tool = FrontendTool(
        name: 'showWeather',
        description: 'Weather',
        parameters: Ack.object({}),
        handler: (_, {required signal}) async => '',
      );
      final entry = AgentContextEntry(
        id: 'e1',
        description: 'Unread',
        value: 3,
      );

      blocTest<CopilotKitClient, CopilotKitState>(
        'AgentOpened opens an agent once',
        build: () => client,
        act: (client) => client
          ..add(const AgentOpened('default'))
          ..add(const AgentOpened('default')),
        expect: () => [
          isA<CopilotKitState>().having(
            (state) => state.agents.keys,
            'agents',
            ['default'],
          ),
        ],
      );

      blocTest<CopilotKitClient, CopilotKitState>(
        'ToolRegistered and ToolUnregistered add and remove the tool',
        build: () => client,
        act: (client) => client
          ..add(ToolRegistered(tool))
          ..add(ToolUnregistered(tool)),
        expect: () => [
          CopilotKitState(tools: {'showWeather': tool}),
          const CopilotKitState(),
        ],
      );

      blocTest<CopilotKitClient, CopilotKitState>(
        'ToolUnregistered ignores an equal tool that is not the registered one',
        build: () => client,
        seed: () => CopilotKitState(tools: {'showWeather': tool}),
        act: (client) => client.add(
          ToolUnregistered(
            FrontendTool(
              name: tool.name,
              description: tool.description,
              parameters: tool.parameters,
              handler: tool.handler,
            ),
          ),
        ),
        expect: () => <CopilotKitState>[],
      );

      blocTest<CopilotKitClient, CopilotKitState>(
        'ContextAdded, ContextUpdated and ContextRemoved edit the context',
        build: () => client,
        act: (client) => client
          ..add(ContextAdded(entry))
          ..add(const ContextUpdated('e1', 4))
          ..add(const ContextRemoved('e1')),
        expect: () => [
          CopilotKitState(context: [entry]),
          CopilotKitState(context: [entry.copyWith(value: 4)]),
          const CopilotKitState(),
        ],
      );
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

        final runIds = transport.sentInputs().map((input) => input.runId);
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
        transport.stubStop();
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
        transport.stubRunThrows(failure);
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
        transport.verifyNoRun();
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

      test('reports errors to the BlocObserver and onError once', () async {
        final observer = _ErrorObserver();
        final previous = Bloc.observer;
        Bloc.observer = observer;
        addTearDown(() => Bloc.observer = previous);
        // A bloc reads the observer when it is created.
        client = CopilotKitClient(
          runtimeUrl: _runtimeUrl,
          onError: (error, stackTrace) => errors.add((error, stackTrace)),
          transport: transport,
        );
        final failure = Exception('connection refused');
        stubRun(Stream.error(failure));

        await client.runAgent(await client.openAgent('default'));

        expect(observer.errors.single.$1, same(client));
        expect(observer.errors.single.$2, same(failure));
        expect(errors.single.$1, same(failure));
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
        transport: MockAgentTransport(),
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
