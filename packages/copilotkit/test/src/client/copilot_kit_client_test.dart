import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mock_agent_transport.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(CopilotKitClient, () {
    final runtimeUrl = Uri.parse('http://runtime.test/api/copilotkit');
    late MockAgentTransport transport;
    late List<(Object, StackTrace)> errors;
    late CopilotKitClient client;

    setUp(() {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: runtimeUrl,
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

    test('starts with no agents, tools or context', () {
      expect(client.agents, isEmpty);
      expect(client.tools, isEmpty);
      expect(client.context, isEmpty);
    });

    test('creates a default transport when none is given', () async {
      final client = CopilotKitClient(runtimeUrl: runtimeUrl);

      await expectLater(client.close(), completes);
    });

    group('tools and context', () {
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

      test('registerTool and unregisterTool add and remove the tool', () {
        client.registerTool(tool);
        expect(client.tools, {'showWeather': tool});

        client.unregisterTool(tool);
        expect(client.tools, isEmpty);
      });

      test('addContext, updateContext and removeContext edit the context', () {
        client.addContext(entry);
        expect(client.context, [entry]);

        client.updateContext('e1', 4);
        expect(client.context, [entry.copyWith(value: 4)]);

        client.removeContext('e1');
        expect(client.context, isEmpty);
      });

      test('exposes read-only views', () {
        expect(() => client.tools['x'] = tool, throwsUnsupportedError);
        expect(() => client.context.add(entry), throwsUnsupportedError);
        expect(
          () => client.agents['x'] = CopilotAgent(agentId: 'x'),
          throwsUnsupportedError,
        );
      });
    });

    group('agent', () {
      test('opens an idle, empty agent once', () {
        final agent = client.agent('default');

        expect(client.agent('default'), same(agent));
        expect(client.agents.keys, ['default']);
        expect(agent.state.agentId, 'default');
        expect(agent.state.messages, isEmpty);
        expect(agent.state.sharedState, isNull);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.toolCalls, isEmpty);
        expect(agent.state.error, isNull);
      });

      test('gives each agent its own thread', () {
        final a = client.agent('a').state.threadId;
        final b = client.agent('b').state.threadId;

        expect(Uuid.isValidUUID(fromString: a), isTrue);
        expect(a, isNot(b));
      });
    });

    group('runAgent', () {
      late CopilotAgent agent;
      final message = UserMessage(id: 'u1', content: 'Hi');

      setUp(() => agent = client.agent('default'));

      test('sends messages, state, properties and headers', () async {
        stubRun(const Stream.empty());
        agent.addMessage(message);

        await client.runAgent('default');

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
      });

      test('appends the given message before the run', () async {
        stubRun(const Stream.empty());

        await client.runAgent('default', message: message);

        expect(sentInput().messages, [message]);
        expect(agent.state.messages, [message]);
      });

      test('opens an agent that was never opened', () async {
        stubRun(const Stream.empty());

        await client.runAgent('other');

        expect(client.agents.keys, ['default', 'other']);
        expect(sentInput().threadId, client.agents['other']!.state.threadId);
      });

      late StreamController<BaseEvent> events;

      test(
        'drops the given message when the agent is already running',
        () async {
          events = StreamController<BaseEvent>();
          stubRun(events.stream);
          final first = client.runAgent('default');
          await pumpEventQueue();

          await client.runAgent('default', message: message);

          events.add(
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          );
          await events.close();
          await first;
          expect(agent.state.messages, isEmpty);
        },
      );

      test('uses a new run id for every run', () async {
        stubRun(const Stream.empty());

        await client.runAgent('default');
        await client.runAgent('default');

        final runIds = transport.sentInputs().map((input) => input.runId);
        expect(runIds.toSet(), hasLength(2));
      });

      test('sends no headers when no builder is given', () async {
        client = CopilotKitClient(runtimeUrl: runtimeUrl, transport: transport);
        stubRun(const Stream.empty());

        await client.runAgent('default');

        verify(
          () => transport.run(
            agentId: 'default',
            input: any(named: 'input'),
          ),
        ).called(1);
      });

      test('streams the assistant reply into messages', () async {
        stubRun(
          Stream.fromIterable([
            RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          ]),
        );
        final texts = <String?>[];
        agent.stream.listen((s) => texts.add(s.messages.lastOrNull?.content));

        await client.runAgent('default');
        await pumpEventQueue();

        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
        expect(errors, isEmpty);
      });

      test('applies state snapshots and deltas to sharedState', () async {
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
        final sharedStates = <Object?>[];
        agent.stream
            .map((state) => state.sharedState)
            .where((shared) => shared != null)
            .distinct()
            .listen(sharedStates.add);

        await client.runAgent('default');
        await pumpEventQueue();

        expect(agent.state.sharedState, {'count': 2});
        expect(sharedStates, [
          {'count': 1},
          {'count': 2},
        ]);
      });

      test('applies the recorded state_snapshot_delta patch', () async {
        stubRun(
          Stream.fromIterable(loadFixture('state_snapshot_delta').events),
        );

        await client.runAgent('default');

        expect(agent.state.sharedState, {
          'todos': ['buy milk', 'walk dog'],
        });
      });

      test('is running as soon as the run starts', () async {
        events = StreamController<BaseEvent>();
        stubRun(events.stream);

        final run = client.runAgent('default');
        await pumpEventQueue();
        expect(agent.state.isRunning, isTrue);

        events.add(
          RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
        );
        await events.close();
        await run;
        expect(agent.state.isRunning, isFalse);
      });

      test('ignores a run while one is in progress', () async {
        events = StreamController<BaseEvent>();
        stubRun(events.stream);
        final first = client.runAgent('default');
        await pumpEventQueue();

        await client.runAgent('default');

        events.add(
          RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
        );
        await events.close();
        await first;
        expect(transport.sentInputs(), hasLength(1));
      });

      final failure = Exception('connection refused');

      test('reports transport errors and ends the run', () async {
        stubRun(Stream.error(failure));

        await client.runAgent('default');

        expect(errors.single.$1, same(failure));
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, same(failure));
      });

      final badTransport = StateError('bad transport');

      test('reports a transport that throws synchronously', () async {
        transport.stubRunThrows(badTransport);

        await client.runAgent('default');

        expect(errors.single.$1, same(badTransport));
        expect(agent.state.isRunning, isFalse);
      });

      test('reports a stream that ends before the run finishes', () async {
        stubRun(
          Stream.value(
            RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
          ),
        );

        await client.runAgent('default');

        expect(errors.single.$1, isA<StateError>());
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, isA<StateError>());
      });

      final noToken = Exception('no token');

      test('reports header builder errors without running', () async {
        client = CopilotKitClient(
          runtimeUrl: runtimeUrl,
          headers: () async => throw noToken,
          onError: (error, stackTrace) => errors.add((error, stackTrace)),
          transport: transport,
        );
        agent = client.agent('default');

        await client.runAgent('default');

        expect(errors.single.$1, same(noToken));
        expect(agent.state.isRunning, isFalse);
        transport.verifyNoRun();
      });

      test(
        'logs errors instead of throwing without an onError handler',
        () async {
          client = CopilotKitClient(
            runtimeUrl: runtimeUrl,
            transport: transport,
          );
          agent = client.agent('default');
          stubRun(Stream.error(Exception('boom')));

          await client.runAgent('default');

          expect(agent.state.error, isA<Exception>());
        },
      );
    });

    group('close', () {
      test('closes the transport and the agents', () async {
        final agent = client.agent('default');
        final changesDone = agent.stream.drain<void>();

        await client.close();

        verify(() => transport.close()).called(1);
        await expectLater(changesDone, completes);
        expect(agent.isClosed, isTrue);
      });

      test('cancels active runs', () async {
        var cancelled = false;
        stubRun(
          StreamController<BaseEvent>(onCancel: () => cancelled = true).stream,
        );
        final run = client.runAgent('default');
        await pumpEventQueue();

        await client.close();
        await run;

        expect(cancelled, isTrue);
      });
    });
  });
}
