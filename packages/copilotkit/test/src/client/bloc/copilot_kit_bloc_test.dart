import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';

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

  group(CopilotKitBloc, () {
    late MockAgentTransport transport;
    late List<(Object, StackTrace)> errors;
    late TestCopilotKitBloc client;

    setUp(() async {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = TestCopilotKitBloc(
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

    /// The input of the only run sent so far.
    RunAgentInput sentInput() => transport.sentInputs().single;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'starts with no agents, tools, context or turns',
      build: () => client,
      verify: (client) => expect(client.state, const CopilotKitState()),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'creates a default transport when none is given',
      build: () => CopilotKitBloc(runtimeUrl: _runtimeUrl),
      expect: () => const <CopilotKitState>[],
    );

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

      blocTest<CopilotKitBloc, CopilotKitState>(
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

      blocTest<CopilotKitBloc, CopilotKitState>(
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

      blocTest<CopilotKitBloc, CopilotKitState>(
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

    group('$AgentOpened', () {
      blocTest<CopilotKitBloc, CopilotKitState>(
        'opens an idle, empty agent once',
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
        verify: (client) {
          final agent = client.state.agents['default']!.state;
          expect(agent.agentId, 'default');
          expect(agent.messages, isEmpty);
          expect(agent.sharedState, isNull);
          expect(agent.isRunning, isFalse);
          expect(agent.toolCalls, isEmpty);
          expect(agent.error, isNull);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'gives each agent its own thread',
        build: () => client,
        act: (client) => client
          ..add(const AgentOpened('a'))
          ..add(const AgentOpened('b')),
        verify: (client) {
          final a = client.state.agents['a']!.state.threadId;
          final b = client.state.agents['b']!.state.threadId;
          expect(Uuid.isValidUUID(fromString: a), isTrue);
          expect(a, isNot(b));
        },
      );
    });

    group('$AgentRunRequested', () {
      late CopilotAgent agent;
      final message = UserMessage(id: 'u1', content: 'Hi');

      setUp(() async => agent = await client.openAgent('default'));

      blocTest<CopilotKitBloc, CopilotKitState>(
        'sends messages, state, properties and headers',
        setUp: () => stubRun(const Stream.empty()),
        build: () => client,
        act: (_) async {
          agent.addMessage(message);
          await client.runAgent(agent);
        },
        verify: (_) {
          final input =
              verify(
                    () => transport.run(
                      agentId: 'default',
                      input: captureAny(named: 'input'),
                      headers: {'Authorization': 'Bearer token'},
                    ),
                  ).captured.single
                  as RunAgentInput;
          expect(input.threadId, agent.state.threadId);
          expect(Uuid.isValidUUID(fromString: input.runId), isTrue);
          expect(input.messages, [message]);
          expect(input.tools, isEmpty);
          expect(input.context, isEmpty);
          expect(input.forwardedProps, {'userId': '42'});
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'appends the given message before the run',
        setUp: () => stubRun(const Stream.empty()),
        build: () => client,
        act: (_) => client.runAgent(agent, message: message),
        verify: (_) {
          expect(sentInput().messages, [message]);
          expect(agent.state.messages, [message]);
        },
      );

      late StreamController<BaseEvent> events;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'drops the given message when the agent is already running',
        setUp: () {
          events = StreamController<BaseEvent>();
          stubRun(events.stream);
        },
        build: () => client,
        act: (_) async {
          final first = client.runAgent(agent);
          await pumpEventQueue();

          await client.runAgent(agent, message: message);

          events.add(
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          );
          await events.close();
          await first;
        },
        verify: (_) => expect(agent.state.messages, isEmpty),
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'uses a new run id for every run',
        setUp: () => stubRun(const Stream.empty()),
        build: () => client,
        act: (_) async {
          await client.runAgent(agent);
          await client.runAgent(agent);
        },
        verify: (_) {
          final runIds = transport.sentInputs().map((input) => input.runId);
          expect(runIds.toSet(), hasLength(2));
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'does nothing when the agent is not open',
        build: () => client,
        act: (client) => client.add(const AgentRunRequested('missing')),
        expect: () => const <CopilotKitState>[],
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'sends no headers when no builder is given',
        setUp: () async {
          client = TestCopilotKitBloc(
            runtimeUrl: _runtimeUrl,
            transport: transport,
          );
          agent = await client.openAgent('default');
          stubRun(const Stream.empty());
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) => verify(
          () => transport.run(
            agentId: 'default',
            input: any(named: 'input'),
          ),
        ).called(1),
      );

      late List<String?> texts;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'streams the assistant reply into messages',
        setUp: () {
          stubRun(
            Stream.fromIterable([
              RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
              const TextMessageStartEvent(messageId: 'm1'),
              const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
              const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
              RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
            ]),
          );
          texts = [];
          agent.stream.listen((s) => texts.add(s.messages.lastOrNull?.content));
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(agent.state.messages.single.content, 'Hello');
          expect(agent.state.isRunning, isFalse);
          expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
          expect(errors, isEmpty);
        },
      );

      late List<Object?> sharedStates;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'applies state snapshots and deltas to sharedState',
        setUp: () {
          stubRun(
            Stream.fromIterable([
              RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
              const StateSnapshotEvent(snapshot: {'count': 1}),
              const TextMessageStartEvent(messageId: 'm1'),
              const StateDeltaEvent(
                delta: [
                  {'op': 'replace', 'path': '/count', 'value': 2},
                ],
              ),
              RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
            ]),
          );
          sharedStates = [];
          agent.stream
              .map((state) => state.sharedState)
              .where((shared) => shared != null)
              .distinct()
              .listen(sharedStates.add);
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(agent.state.sharedState, {'count': 2});
          expect(sharedStates, [
            {'count': 1},
            {'count': 2},
          ]);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'applies the recorded state_snapshot_delta patch',
        setUp: () => stubRun(
          Stream.fromIterable(loadFixture('state_snapshot_delta').events),
        ),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) => expect(agent.state.sharedState, {
          'todos': ['buy milk', 'walk dog'],
        }),
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'is running as soon as the run starts',
        setUp: () {
          events = StreamController<BaseEvent>();
          stubRun(events.stream);
        },
        build: () => client,
        act: (_) async {
          final run = client.runAgent(agent);
          await pumpEventQueue();
          expect(agent.state.isRunning, isTrue);

          events.add(
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          );
          await events.close();
          await run;
        },
        verify: (_) => expect(agent.state.isRunning, isFalse),
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'ignores a run while one is in progress',
        setUp: () {
          events = StreamController<BaseEvent>();
          stubRun(events.stream);
        },
        build: () => client,
        act: (_) async {
          final first = client.runAgent(agent);
          await pumpEventQueue();

          await client.runAgent(agent);

          events.add(
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          );
          await events.close();
          await first;
        },
        verify: (_) => verify(
          () => transport.run(
            agentId: any(named: 'agentId'),
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).called(1),
      );

      final failure = Exception('connection refused');

      blocTest<CopilotKitBloc, CopilotKitState>(
        'reports transport errors and ends the run',
        setUp: () => stubRun(Stream.error(failure)),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(errors.single.$1, same(failure));
          expect(agent.state.isRunning, isFalse);
          expect(agent.state.error, same(failure));
        },
      );

      final badTransport = StateError('bad transport');

      blocTest<CopilotKitBloc, CopilotKitState>(
        'reports a transport that throws synchronously',
        setUp: () => transport.stubRunThrows(badTransport),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(errors.single.$1, same(badTransport));
          expect(agent.state.isRunning, isFalse);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'reports a stream that ends before the run finishes',
        setUp: () => stubRun(
          Stream.value(
            RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
          ),
        ),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(errors.single.$1, isA<StateError>());
          expect(agent.state.isRunning, isFalse);
          expect(agent.state.error, isA<StateError>());
        },
      );

      final noToken = Exception('no token');

      blocTest<CopilotKitBloc, CopilotKitState>(
        'reports header builder errors without running',
        setUp: () async {
          client = TestCopilotKitBloc(
            runtimeUrl: _runtimeUrl,
            headers: () async => throw noToken,
            onError: (error, stackTrace) => errors.add((error, stackTrace)),
            transport: transport,
          );
          agent = await client.openAgent('default');
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(errors.single.$1, same(noToken));
          expect(agent.state.isRunning, isFalse);
          transport.verifyNoRun();
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'does not throw without an onError handler',
        setUp: () async {
          client = TestCopilotKitBloc(
            runtimeUrl: _runtimeUrl,
            transport: transport,
          );
          agent = await client.openAgent('default');
          stubRun(Stream.error(Exception('boom')));
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) => expect(agent.state.error, isA<Exception>()),
      );

      late _ErrorObserver observer;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'reports errors to the BlocObserver and onError once',
        setUp: () async {
          observer = _ErrorObserver();
          final previous = Bloc.observer;
          Bloc.observer = observer;
          addTearDown(() => Bloc.observer = previous);
          // A bloc reads the observer when it is created.
          client = TestCopilotKitBloc(
            runtimeUrl: _runtimeUrl,
            onError: (error, stackTrace) => errors.add((error, stackTrace)),
            transport: transport,
          );
          agent = await client.openAgent('default');
          stubRun(Stream.error(failure));
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (client) {
          expect(observer.errors.single.$1, same(client));
          expect(observer.errors.single.$2, same(failure));
          expect(errors.single.$1, same(failure));
        },
      );
    });

    group('close', () {
      late CopilotAgent agent;
      late Future<void> changesDone;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'closes the transport and the agents',
        build: () => client,
        act: (_) async {
          agent = await client.openAgent('default');
          changesDone = agent.stream.drain<void>();
        },
        verify: (_) async {
          verify(() => transport.close()).called(1);
          await expectLater(changesDone, completes);
          expect(agent.isClosed, isTrue);
        },
      );

      late bool cancelled;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'cancels active runs',
        setUp: () {
          cancelled = false;
          stubRun(
            StreamController<BaseEvent>(onCancel: () => cancelled = true)
                .stream,
          );
        },
        build: () => client,
        act: (bloc) async {
          agent = await client.openAgent('default');
          final run = client.runAgent(agent);
          await pumpEventQueue();

          await bloc.close();
          await run;
        },
        verify: (_) => expect(cancelled, isTrue),
      );
    });
  });
}
