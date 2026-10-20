import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/json_values.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

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
        properties: const JsonObject({'userId': '42'}),
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
        decode: JsonObject.new,
        handler: (_, {required signal}) async => '',
      );
      final entry = AgentContextEntry(
        id: 'e1',
        description: 'Unread',
        value: const Count(3),
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

        client.updateContext('e1', const Count(4));
        expect(client.context, [entry.copyWith(value: const Count(4))]);

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

        expect(agent.state.sharedState, const SharedState({'count': 2}));
        expect(sharedStates, [
          const SharedState({'count': 1}),
          const SharedState({'count': 2}),
        ]);
      });

      test('applies the recorded state_snapshot_delta patch', () async {
        stubRun(
          Stream.fromIterable(loadFixture('state_snapshot_delta').events),
        );

        await client.runAgent('default');

        expect(
          agent.state.sharedState,
          const SharedState({
            'todos': ['buy milk', 'walk dog'],
          }),
        );
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

    group('human-in-the-loop tools', () {
      late ClientHarness harness;
      late CopilotKitClient client;
      late CopilotAgent agent;
      late List<Stream<BaseEvent>> runs;
      late HumanInTheLoopTool<JsonObject> tool;
      late Future<void> run;
      late CopilotAgentState waiting;
      // The inputs of every run, read once: the mock counts a verified call
      // only once.
      List<RunAgentInput>? inputs;

      setUp(() {
        harness = ClientHarness();
        client = harness.client;
        agent = harness.agent;
        runs = harness.runs;
        tool = approvalTool();
        inputs = null;
        client.registerTool(tool);
      });

      List<RunAgentInput> sentInputs() =>
          inputs ??= harness.transport.sentInputs();

      String threadId() => agent.state.threadId;

      /// Queues a run that calls the tool for each of [ids], then a reply.
      void queueCallsAndReply({List<String> ids = const ['c1']}) {
        runs
          ..add(Stream.fromIterable(approvalRun(threadId(), ids: ids)))
          ..add(Stream.fromIterable(replyRun(threadId())));
      }

      /// Starts the turn and waits until it is blocked on the user.
      Future<void> startRun() async {
        run = client.runAgent(agent.state.agentId);
        await pumpEventQueue();
        waiting = agent.state;
      }

      /// The tool messages of the conversation sent with the last run, by call.
      Map<String, String> sentResults() => {
        for (final message
            in sentInputs().last.messages.whereType<ToolMessage>())
          message.toolCallId: message.content,
      };

      test(
        'marks the call as awaiting while the agent stays running',
        () async {
          queueCallsAndReply();

          await startRun();
          client.respondToToolCall('c1', 'ok');
          await run;

          final call = waiting.toolCalls.single;
          expect(call.status, ToolCallStatus.executing);
          expect(call.awaitingResponse, isTrue);
          expect(waiting.awaitingResponseIds, ['c1']);
          expect(waiting.isRunning, isTrue);
        },
      );

      test('sends the answer as the tool result and runs again', () async {
        queueCallsAndReply();

        await startRun();
        client.respondToToolCall('c1', 'approved');
        await run;

        expect(sentInputs(), hasLength(2));
        expect(sentResults(), {'c1': 'approved'});
        final call = agent.state.toolCalls.single;
        expect(call.status, ToolCallStatus.complete);
        expect(call.result, 'approved');
        expect(call.awaitingResponse, isFalse);
        expect(agent.state.awaitingResponseIds, isEmpty);
        expect(agent.state.messages.last.content, 'Sunny in Lima');
        expect(agent.state.isRunning, isFalse);
        expect(harness.errors, isEmpty);
      });

      test('sends the tool to the agent', () async {
        queueCallsAndReply();

        await startRun();
        client.respondToToolCall('c1', 'ok');
        await run;

        expect(sentInputs().first.tools.single.name, 'confirmAction');
      });

      test('JSON-encodes an answer that is not a string', () async {
        queueCallsAndReply();

        await startRun();
        client.respondToToolCall('c1', {'decision': 'approve', 'count': 2});
        await run;

        expect(sentResults(), {'c1': '{"decision":"approve","count":2}'});
      });

      group('an answer that arrives before the turn waits for the call', () {
        late StreamController<BaseEvent> events;

        setUp(() {
          events = StreamController<BaseEvent>();
          runs
            ..add(events.stream)
            ..add(Stream.fromIterable(replyRun(threadId())));
        });

        test('is kept until the run has finished streaming', () async {
          run = client.runAgent(agent.state.agentId);
          events.add(RunStartedEvent(threadId: threadId(), runId: 'r1'));
          approvalCall('c1').forEach(events.add);
          await pumpEventQueue();
          // The call is complete, but the run has not finished: the turn
          // doesn't wait for it yet.
          expect(agent.state.awaitingResponseIds, isEmpty);

          client.respondToToolCall('c1', 'early');
          events.add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await run;

          expect(sentResults(), {'c1': 'early'});
        });

        test('is ignored while the arguments still stream', () async {
          run = client.runAgent(agent.state.agentId);
          events
            ..add(RunStartedEvent(threadId: threadId(), runId: 'r1'))
            ..add(
              const ToolCallStartEvent(
                toolCallId: 'c1',
                toolCallName: 'confirmAction',
                parentMessageId: 'a1',
              ),
            )
            ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"act'));
          await pumpEventQueue();

          client.respondToToolCall('c1', 'too early');
          events
            ..add(
              const ToolCallArgsEvent(toolCallId: 'c1', delta: 'ion": "x"}'),
            )
            ..add(const ToolCallEndEvent(toolCallId: 'c1'))
            ..add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await pumpEventQueue();
          waiting = agent.state;
          client.respondToToolCall('c1', 'on time');
          await run;

          expect(waiting.awaitingResponseIds, ['c1']);
          expect(sentResults(), {'c1': 'on time'});
        });
      });

      test(
        'stop while awaiting answers the call as cancelled and ends the turn',
        () async {
          runs.add(Stream.fromIterable(approvalRun(threadId())));

          await startRun();
          await client.stopAgent(agent.state.agentId);
          await run;

          expect(sentInputs(), hasLength(1));
          final call = agent.state.toolCalls.single;
          expect(call.status, ToolCallStatus.complete);
          expect(call.result, 'Tool call cancelled.');
          expect(call.awaitingResponse, isFalse);
          expect(agent.state.isRunning, isFalse);
          harness.transport.verifyNoStop();
        },
      );

      test('an answer after a stop is ignored', () async {
        runs.add(Stream.fromIterable(approvalRun(threadId())));

        await startRun();
        await client.stopAgent(agent.state.agentId);
        await run;
        client.respondToToolCall('c1', 'too late');

        expect(agent.state.toolCalls.single.result, 'Tool call cancelled.');
        expect(agent.state.messages.whereType<ToolMessage>(), hasLength(1));
      });

      test('closing the client while awaiting ends the turn', () async {
        runs.add(Stream.fromIterable(approvalRun(threadId())));

        await startRun();
        await client.close();
        await run;

        expect(sentInputs(), hasLength(1));
      });

      test(
        'two calls wait together and can be answered out of order',
        () async {
          queueCallsAndReply(ids: const ['c1', 'c2']);

          await startRun();
          client.respondToToolCall('c2', 'second');
          await pumpEventQueue();
          final mid = agent.state.awaitingResponseIds;
          client.respondToToolCall('c1', 'first');
          await run;

          expect(waiting.awaitingResponseIds, ['c1', 'c2']);
          expect(mid, ['c1', 'c2']);
          expect(sentResults(), {'c1': 'first', 'c2': 'second'});
          final messages = sentInputs().last.messages;
          expect(messages.whereType<ToolMessage>().map((m) => m.toolCallId), [
            'c1',
            'c2',
          ]);
          expect(agent.state.awaitingResponseIds, isEmpty);
        },
      );

      test(
        'ignores a duplicate answer and answers for unknown calls',
        () async {
          queueCallsAndReply();

          await startRun();
          client
            ..respondToToolCall('missing', 'nobody asked')
            ..respondToToolCall('c1', 'first')
            ..respondToToolCall('c1', 'second');
          await run;
          client.respondToToolCall('c1', 'third');

          expect(sentResults(), {'c1': 'first'});
          expect(agent.state.toolCalls.single.result, 'first');
          expect(harness.errors, isEmpty);
        },
      );

      test('ignores an answer for a call of a frontend tool', () async {
        client.registerTool(
          weatherTool((_, {required signal}) async => 'sunny'),
        );
        runs
          ..add(Stream.fromIterable(toolCallRun(threadId())))
          ..add(Stream.fromIterable(replyRun(threadId())));

        run = client.runAgent(agent.state.agentId);
        await pumpEventQueue();
        client.respondToToolCall('c1', 'not for you');
        await run;

        expect(sentResults(), {'c1': 'sunny'});
      });

      test('an answer that cannot be encoded is reported and the call keeps '
          'waiting', () async {
        queueCallsAndReply();

        await startRun();
        client.respondToToolCall('c1', DateTime(2026));
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        client.respondToToolCall('c1', 'fine');
        await run;

        expect(harness.errors.single, isA<JsonUnsupportedObjectError>());
        expect(mid, ['c1']);
        expect(sentResults(), {'c1': 'fine'});
      });

      group('unregistering the tool while a call waits', () {
        test('answers the call as cancelled and continues the turn', () async {
          queueCallsAndReply();

          await startRun();
          client.unregisterTool(tool);
          await run;

          expect(sentInputs(), hasLength(2));
          expect(sentResults(), {'c1': 'Tool call cancelled.'});
          expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
          expect(agent.state.isRunning, isFalse);
        });

        test(
          'keeps the call waiting when the tool was replaced first',
          () async {
            queueCallsAndReply();

            await startRun();
            client
              ..registerTool(
                HumanInTheLoopTool(
                  name: tool.name,
                  description: 'An updated description',
                  parameters: tool.parameters,
                  decode: JsonObject.new,
                ),
              )
              ..unregisterTool(tool);
            await pumpEventQueue();
            final mid = agent.state.awaitingResponseIds;
            client.respondToToolCall('c1', 'still here');
            await run;

            expect(mid, ['c1']);
            expect(sentResults(), {'c1': 'still here'});
          },
        );

        test('leaves the calls of other tools alone', () async {
          queueCallsAndReply();

          await startRun();
          client
            ..unregisterTool(
              HumanInTheLoopTool(
                name: 'other',
                description: 'Another tool',
                parameters: Ack.object({}),
                decode: JsonObject.new,
              ),
            )
            ..respondToToolCall('c1', 'ok');
          await run;

          expect(sentResults(), {'c1': 'ok'});
        });
      });

      test(
        'closes a call of an unregistered tool as unavailable without waiting',
        () async {
          client.unregisterTool(tool);
          runs
            ..add(Stream.fromIterable(approvalRun(threadId())))
            ..add(Stream.fromIterable(replyRun(threadId())));

          await client.runAgent(agent.state.agentId);

          final call = agent.state.toolCalls.single;
          expect(call.result, 'Tool is not available.');
          expect(call.awaitingResponse, isFalse);
        },
      );

      test(
        'answers arguments that do not match the schema without waiting',
        () async {
          runs
            ..add(
              Stream.fromIterable(
                approvalRun(threadId(), args: '{"action": 1}'),
              ),
            )
            ..add(Stream.fromIterable(replyRun(threadId())));

          await client.runAgent(agent.state.agentId);

          expect(sentResults()['c1'], contains("arguments don't match"));
          expect(agent.state.awaitingResponseIds, isEmpty);
        },
      );

      group('followUp', () {
        test('false ends the turn without another run', () async {
          tool = approvalTool(followUp: false);
          client.registerTool(tool);
          runs.add(Stream.fromIterable(approvalRun(threadId())));

          await startRun();
          client.respondToToolCall('c1', 'noted');
          await run;

          expect(sentInputs(), hasLength(1));
          final call = agent.state.toolCalls.single;
          expect(call.status, ToolCallStatus.complete);
          expect(call.result, 'noted');
          expect(
            agent.state.messages.whereType<ToolMessage>().single.content,
            'noted',
          );
          expect(agent.state.isRunning, isFalse);
        });

        test(
          'false still runs again when another call in the turn follows up',
          () async {
            client
              ..registerTool(approvalTool(followUp: false))
              ..registerTool(
                weatherTool((_, {required signal}) async => 'sunny'),
              );
            runs
              ..add(
                Stream.fromIterable([
                  RunStartedEvent(threadId: threadId(), runId: 'r1'),
                  ...approvalCall('c1'),
                  const ToolCallStartEvent(
                    toolCallId: 'c2',
                    toolCallName: 'showWeather',
                    parentMessageId: 'a1',
                  ),
                  const ToolCallArgsEvent(
                    toolCallId: 'c2',
                    delta: '{"city": "Lima"}',
                  ),
                  const ToolCallEndEvent(toolCallId: 'c2'),
                  RunFinishedEvent(threadId: threadId(), runId: 'r1'),
                ]),
              )
              ..add(Stream.fromIterable(replyRun(threadId())));

            await startRun();
            client.respondToToolCall('c1', 'noted');
            await run;

            expect(sentInputs(), hasLength(2));
            expect(sentResults(), {'c1': 'noted', 'c2': 'sunny'});
          },
        );
      });

      test('isRunning stays true until the end of the turn', () async {
        queueCallsAndReply();
        final running = <bool>[];
        agent.stream.listen((state) => running.add(state.isRunning));

        await startRun();
        client.respondToToolCall('c1', 'ok');
        await run;
        // The stream delivers the last state after the turn completes.
        await pumpEventQueue();

        expect(running.first, isTrue);
        expect(running.sublist(0, running.length - 1), everyElement(isTrue));
        expect(running.last, isFalse);
      });
    });
  });
}
