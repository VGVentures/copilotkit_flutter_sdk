import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/json_values.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/runner_harness.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(AgentRunner, () {
    late RunnerHarness harness;
    late AgentRunner runner;
    late MockAgentTransport transport;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;
    late List<Object> errors;

    void useHarness(RunnerHarness next) {
      harness = next;
      runner = next.runner;
      transport = next.transport;
      agent = next.agent;
      runs = next.runs;
      errors = next.errors;
    }

    setUp(() => useHarness(RunnerHarness()));

    String threadId() => agent.state.threadId;

    List<RunAgentInput> sentInputs() => transport.sentInputs();

    void queueRun(List<BaseEvent> events) =>
        runs.add(Stream.fromIterable(events));

    /// Records whether the agent was running on every state it emits.
    List<bool> recordRunning() {
      final running = <bool>[];
      agent.stream.listen((state) => running.add(state.isRunning));
      return running;
    }

    group('run', () {
      final message = UserMessage(id: 'u1', content: 'Hi');

      test('sends the agent, tools, context, properties and headers', () async {
        useHarness(
          RunnerHarness(
            headers: () async => {'Authorization': 'Bearer token'},
            properties: const JsonObject({'userId': '42'}),
          ),
        );
        harness.tools.register(weatherTool((_, {required signal}) async => ''));
        harness.context.add(
          AgentContextEntry(description: 'Unread', value: const Count(3)),
        );
        agent.addMessage(message);
        runs.add(const Stream.empty());

        await runner.run(agent);

        final input =
            verify(
                  () => transport.run(
                    agentId: 'default',
                    input: captureAny(named: 'input'),
                    headers: {'Authorization': 'Bearer token'},
                  ),
                ).captured.single
                as RunAgentInput;
        expect(input.threadId, threadId());
        expect(Uuid.isValidUUID(fromString: input.runId), isTrue);
        expect(input.messages, [message]);
        expect(input.tools.single.name, 'showWeather');
        expect(input.context.single.value, '3');
        expect(input.forwardedProps, {'userId': '42'});
      });

      test(
        'sends the state and messages the agent has when it starts',
        () async {
          runs.add(const Stream.empty());

          agent
            ..setSharedState(const SharedState({'count': 3}))
            ..patchSharedState(const [
              JsonPatchReplace(path: '/count', value: 4),
            ])
            ..addMessage(UserMessage(id: 'old', content: 'Old'))
            ..setMessages([UserMessage(id: 'new', content: 'New')]);
          await runner.run(agent);

          final input = sentInputs().single;
          expect(input.state, {'count': 4});
          expect(input.messages.map((message) => message.id), ['new']);
        },
      );

      test('appends the given message before the run', () async {
        runs.add(const Stream.empty());

        await runner.run(agent, message: message);

        expect(sentInputs().single.messages, [message]);
        expect(agent.state.messages, [message]);
      });

      late StreamController<BaseEvent> events;

      test(
        'drops the given message when the agent is already running',
        () async {
          events = StreamController<BaseEvent>();
          runs.add(events.stream);
          final first = runner.run(agent);
          await pumpEventQueue();

          await runner.run(agent, message: message);

          events.add(RunFinishedEvent(threadId: threadId(), runId: 'r'));
          await events.close();
          await first;
          expect(agent.state.messages, isEmpty);
        },
      );

      test('uses a new run id for every run', () async {
        runs.addAll([const Stream.empty(), const Stream.empty()]);

        await runner.run(agent);
        await runner.run(agent);

        final runIds = sentInputs().map((input) => input.runId);
        expect(runIds.toSet(), hasLength(2));
      });

      test('sends no headers when no builder is given', () async {
        runs.add(const Stream.empty());

        await runner.run(agent);

        verify(
          () => transport.run(
            agentId: 'default',
            input: any(named: 'input'),
          ),
        ).called(1);
      });

      test('streams the assistant reply into messages', () async {
        queueRun([
          RunStartedEvent(threadId: threadId(), runId: 'r'),
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
          RunFinishedEvent(threadId: threadId(), runId: 'r'),
        ]);
        final texts = <String?>[];
        agent.stream.listen((s) => texts.add(s.messages.lastOrNull?.content));

        await runner.run(agent);
        await pumpEventQueue();

        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(texts, containsAllInOrder(['', 'Hel', 'Hello']));
        expect(errors, isEmpty);
      });

      test('applies state snapshots and deltas to sharedState', () async {
        queueRun([
          RunStartedEvent(threadId: threadId(), runId: 'r'),
          const StateSnapshotEvent(snapshot: {'count': 1}),
          const TextMessageStartEvent(messageId: 'm1'),
          const StateDeltaEvent(
            delta: [
              {'op': 'replace', 'path': '/count', 'value': 2},
            ],
          ),
          RunFinishedEvent(threadId: threadId(), runId: 'r'),
        ]);
        final sharedStates = <Object?>[];
        agent.stream
            .map((state) => state.sharedState)
            .where((shared) => shared != null)
            .distinct()
            .listen(sharedStates.add);

        await runner.run(agent);
        await pumpEventQueue();

        expect(agent.state.sharedState, const SharedState({'count': 2}));
        expect(sharedStates, [
          const SharedState({'count': 1}),
          const SharedState({'count': 2}),
        ]);
      });

      test('applies the recorded state_snapshot_delta patch', () async {
        queueRun(loadFixture('state_snapshot_delta').events);

        await runner.run(agent);

        expect(
          agent.state.sharedState,
          const SharedState({
            'todos': ['buy milk', 'walk dog'],
          }),
        );
      });

      test('the state the runtime sends replaces a local edit', () async {
        queueRun([
          RunStartedEvent(threadId: threadId(), runId: 'r1'),
          const StateSnapshotEvent(snapshot: {'count': 1}),
          RunFinishedEvent(threadId: threadId(), runId: 'r1'),
        ]);

        agent.setSharedState(const SharedState({'count': 3}));
        await runner.run(agent);

        expect(sentInputs().single.state, {'count': 3});
        expect(agent.state.sharedState, const SharedState({'count': 1}));
      });

      test('is running as soon as the run starts', () async {
        events = StreamController<BaseEvent>();
        runs.add(events.stream);

        final run = runner.run(agent);
        await pumpEventQueue();
        expect(agent.state.isRunning, isTrue);

        events.add(RunFinishedEvent(threadId: threadId(), runId: 'r'));
        await events.close();
        await run;
        expect(agent.state.isRunning, isFalse);
      });

      test('ignores a run while one is in progress', () async {
        events = StreamController<BaseEvent>();
        runs.add(events.stream);
        final first = runner.run(agent);
        await pumpEventQueue();

        await runner.run(agent);

        events.add(RunFinishedEvent(threadId: threadId(), runId: 'r'));
        await events.close();
        await first;
        expect(sentInputs(), hasLength(1));
      });

      final failure = Exception('connection refused');

      test('reports transport errors and ends the run', () async {
        runs.add(Stream.error(failure));

        await runner.run(agent);

        expect(errors.single, same(failure));
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, same(failure));
      });

      final badTransport = StateError('bad transport');

      test('reports a transport that throws synchronously', () async {
        transport.stubRunThrows(badTransport);

        await runner.run(agent);

        expect(errors.single, same(badTransport));
        expect(agent.state.isRunning, isFalse);
      });

      test('reports a stream that ends before the run finishes', () async {
        queueRun([RunStartedEvent(threadId: threadId(), runId: 'r')]);

        await runner.run(agent);

        expect(errors.single, isA<StateError>());
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, isA<StateError>());
      });

      final noToken = Exception('no token');

      test('reports header builder errors without running', () async {
        useHarness(RunnerHarness(headers: () async => throw noToken));

        await runner.run(agent);

        expect(errors.single, same(noToken));
        expect(agent.state.isRunning, isFalse);
        transport.verifyNoRun();
      });

      test(
        'reports a context value that is not JSON without running',
        () async {
          harness.context.add(
            AgentContextEntry(
              description: 'Clock',
              value: const NonJsonValue(),
            ),
          );

          await runner.run(agent);

          expect(errors.single, isA<JsonUnsupportedObjectError>());
          transport.verifyNoRun();
        },
      );
    });

    group('resilience', () {
      test(
        'reasoning, activity, raw and custom events leave text intact',
        () async {
          queueRun([
            RunStartedEvent(threadId: threadId(), runId: 'r'),
            const ReasoningStartEvent(messageId: 'think'),
            const ReasoningMessageContentEvent(
              messageId: 'think',
              delta: 'Hmm',
            ),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
            const ActivitySnapshotEvent(
              messageId: 'act',
              activityType: 'search',
              content: {'query': 'weather'},
            ),
            const ThinkingStartEvent(title: 'plan'),
            const RawEvent(event: {'anything': true}),
            const CustomEvent(name: 'progress', value: 0.5),
            const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
            RunFinishedEvent(threadId: threadId(), runId: 'r'),
          ]);

          await runner.run(agent);

          expect(agent.state.messages.single.content, 'Hello');
          expect(agent.state.isRunning, isFalse);
          expect(errors, isEmpty);
        },
      );

      const runError = RunErrorEvent(message: 'Invalid API key', code: 'AUTH');

      test('RUN_ERROR ends the run and reports the error once', () async {
        queueRun([
          RunStartedEvent(threadId: threadId(), runId: 'r'),
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Par'),
          runError,
        ]);

        await runner.run(agent);

        expect(errors, [same(runError)]);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, same(runError));
        expect(agent.state.messages.single.content, 'Par');
      });

      test('unknown_events fixture keeps the text reply', () async {
        queueRun(loadFixture('unknown_events').events);

        await runner.run(agent);

        expect(
          agent.state.messages.single.content,
          'Hello! Wonderful to meet you.',
        );
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      test('recorded run_error fixture reports the runtime error', () async {
        queueRun(loadFixture('run_error').events);

        await runner.run(agent);

        expect(errors.single, isA<RunErrorEvent>());
        expect(
          agent.state.error,
          isA<RunErrorEvent>().having(
            (error) => error.message,
            'message',
            contains('gemini-2.5-flash'),
          ),
        );
        expect(agent.state.isRunning, isFalse);
      });

      test(
        'dropped_connection fixture fails the run and keeps the partial reply',
        () async {
          queueRun(loadFixture('dropped_connection').events);

          await runner.run(agent);

          expect(errors.single, isA<StateError>());
          expect(agent.state.messages.single.content, 'Hello! Wonderful to');
          expect(agent.state.isRunning, isFalse);
        },
      );
    });

    group('stop', () {
      late StreamController<BaseEvent> events;
      late bool cancelled;
      late Future<void> run;

      /// Uses a harness with [headers] whose runs stream [events].
      void useStreamingHarness({
        HeadersBuilder? headers,
        CopilotErrorHandler? onError,
      }) {
        useHarness(
          RunnerHarness(
            headers: headers ?? () async => {'Authorization': 'Bearer token'},
            onError: onError,
          ),
        );
        transport.stubRun(() => events.stream);
      }

      setUp(() {
        cancelled = false;
        events = StreamController<BaseEvent>(onCancel: () => cancelled = true);
        useStreamingHarness();
      });

      Future<void> startStreaming() async {
        run = runner.run(agent);
        events
          ..add(RunStartedEvent(threadId: threadId(), runId: 'r'))
          ..add(const TextMessageStartEvent(messageId: 'm1'))
          ..add(const TextMessageContentEvent(messageId: 'm1', delta: 'Hal'));
        await pumpEventQueue();
      }

      Future<void> stopStreaming() async {
        await runner.stop(agent);
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

          final runId = sentInputs().single.runId;
          verify(
            () => transport.stop(
              agentId: 'default',
              threadId: threadId(),
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
          useStreamingHarness(headers: () => headers.future);
        });

        test('stop sends no request', () async {
          run = runner.run(agent);
          await pumpEventQueue();

          await runner.stop(agent);
          headers.complete({});
          await run;

          transport.verifyNoRun();
          expect(agent.state.isRunning, isFalse);
          expect(errors, isEmpty);
        });

        test('close sends no request', () async {
          run = runner.run(agent);
          await pumpEventQueue();

          await runner.close();
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
          useStreamingHarness(onError: (_, _) => stop ??= runner.stop(agent));

          run = runner.run(agent);
          await pumpEventQueue();
          end(events);
          await run;
          await stop;

          expect(stop, isNotNull);
          expect(agent.state.isRunning, isFalse);
        });
      }

      test('does nothing when the agent is not running', () async {
        await runner.stop(agent);

        expect(agent.state.isRunning, isFalse);
        transport.verifyNoStop();
      });

      test('can be interrupted by close', () async {
        await startStreaming();

        final stop = runner.stop(agent);
        await runner.close();
        await agent.close();
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
            RunStartedEvent(threadId: threadId(), runId: 'r2'),
            const TextMessageStartEvent(messageId: 'm2'),
            const TextMessageContentEvent(messageId: 'm2', delta: 'Again'),
            RunFinishedEvent(threadId: threadId(), runId: 'r2'),
          ]),
        );

        await runner.run(agent);

        expect(agent.state.isRunning, isFalse);
        expect(agent.state.messages.map((m) => m.content), ['Hal', 'Again']);
      });

      test('stops one agent while another keeps running', () async {
        final otherEvents = StreamController<BaseEvent>();
        final other = CopilotAgent(agentId: 'other');
        when(
          () => transport.run(
            agentId: 'other',
            input: any(named: 'input'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) => otherEvents.stream);

        await startStreaming();
        final otherRun = runner.run(other);
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

    group('close', () {
      test('cancels active runs', () async {
        var cancelled = false;
        runs.add(
          StreamController<BaseEvent>(onCancel: () => cancelled = true).stream,
        );
        final run = runner.run(agent);
        await pumpEventQueue();

        await runner.close();
        await run;

        expect(cancelled, isTrue);
      });
    });

    group('frontend tools', () {
      /// Queues a run calling the tool, then a run replying to its result.
      void queueToolCallAndReply() {
        queueRun(toolCallRun(threadId()));
        queueRun(replyRun(threadId()));
      }

      void registerTool(ClientTool<Object?> tool) =>
          harness.tools.register(tool);

      JsonObject? receivedArgs;
      CancellationSignal? receivedSignal;
      late List<ToolCallStatus> statuses;

      test('runs the handler, sends the result and runs again', () async {
        registerTool(
          weatherTool((args, {required signal}) async {
            receivedArgs = args;
            receivedSignal = signal;
            return '{"forecast": "sunny"}';
          }),
        );
        queueToolCallAndReply();
        statuses = [];
        agent.stream.listen((s) {
          final status = s.toolCalls.firstOrNull?.status;
          if (status != null && statuses.lastOrNull != status) {
            statuses.add(status);
          }
        });

        await runner.run(agent);

        expect(receivedArgs, const JsonObject({'city': 'Lima'}));
        expect(receivedSignal!.isCancelled, isFalse);
        final inputs = sentInputs();
        expect(inputs, hasLength(2));
        final followUp = inputs.last.messages;
        final assistant = followUp[followUp.length - 2] as AssistantMessage;
        expect(
          assistant.toolCalls!.single.function.arguments,
          '{"city": "Lima"}',
        );
        final toolMessage = followUp.last as ToolMessage;
        expect(Uuid.isValidUUID(fromString: toolMessage.id!), isTrue);
        expect(toolMessage.toolCallId, 'c1');
        expect(toolMessage.content, '{"forecast": "sunny"}');
        expect(agent.state.toolCalls.single.result, '{"forecast": "sunny"}');
        expect(statuses, [
          ToolCallStatus.inProgress,
          ToolCallStatus.executing,
          ToolCallStatus.complete,
        ]);
        expect(agent.state.messages.last.content, 'Sunny in Lima');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      late Completer<String> handlerDone;

      test('stays running while the handler runs', () async {
        handlerDone = Completer<String>();
        registerTool(weatherTool((_, {required signal}) => handlerDone.future));
        queueToolCallAndReply();

        final run = runner.run(agent);
        await pumpEventQueue();
        expect(agent.state.isRunning, isTrue);
        expect(agent.state.toolCalls.single.status, ToolCallStatus.executing);

        handlerDone.complete('ok');
        await run;

        expect(agent.state.isRunning, isFalse);
      });

      late List<bool> running;

      test('stays running from the first run to the end of the turn', () async {
        registerTool(weatherTool((_, {required signal}) async => 'ok'));
        queueToolCallAndReply();
        running = recordRunning();

        await runner.run(agent);
        // The stream delivers the last state after the turn completes.
        await pumpEventQueue();

        expect(running.last, isFalse);
        expect(running.sublist(0, running.length - 1), everyElement(isTrue));
      });

      test('stays running until a failed turn ends', () async {
        queueRun([
          RunStartedEvent(threadId: threadId(), runId: 'r1'),
          const RunErrorEvent(message: 'model error'),
        ]);
        running = recordRunning();

        await runner.run(agent);
        // The stream delivers the last state after the turn completes.
        await pumpEventQueue();

        expect(running.last, isFalse);
        expect(running.sublist(0, running.length - 1), everyElement(isTrue));
        expect(errors, hasLength(1));
      });

      final failure = Exception('no network');

      test(
        'turns handler errors into a generic result and reports them',
        () async {
          registerTool(
            weatherTool((_, {required signal}) async => throw failure),
          );
          queueToolCallAndReply();

          await runner.run(agent);

          expect(errors, [same(failure)]);
          final toolMessage = sentInputs().last.messages.last as ToolMessage;
          expect(toolMessage.content, 'Tool failed.');
          expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
        },
      );

      test('passes the handler the args parsed by the schema', () async {
        receivedArgs = null;
        registerTool(
          FrontendTool<JsonObject>(
            name: 'showWeather',
            description: 'Show the weather for a city',
            parameters: Ack.object({
              'city': Ack.string(),
              'days': Ack.integer().withDefault(3),
            }),
            decode: JsonObject.new,
            handler: (args, {required signal}) async {
              receivedArgs = args;
              return 'ok';
            },
          ),
        );
        queueToolCallAndReply();

        await runner.run(agent);

        expect(receivedArgs, const JsonObject({'city': 'Lima', 'days': 3}));
      });

      late bool called;

      /// Registers the weather tool with a handler that records it was
      /// called.
      void registerRecordingTool() {
        called = false;
        registerTool(
          weatherTool((_, {required signal}) async {
            called = true;
            return '';
          }),
        );
      }

      test('answers invalid args without running the handler', () async {
        registerRecordingTool();
        queueRun(
          toolCallRun(threadId())
            ..[2] = const ToolCallArgsEvent(
              toolCallId: 'c1',
              delta: '{"days": "3"}',
            ),
        );
        queueRun(replyRun(threadId()));

        await runner.run(agent);

        expect(called, isFalse);
        expect(errors, isEmpty);
        final result = agent.state.toolCalls.single.result;
        expect(
          result,
          allOf(
            startsWith("The tool didn't run"),
            contains('- city: Required property "city" is missing.'),
            contains('- days: Expected integer, got string.'),
          ),
        );
        final toolMessage = sentInputs().last.messages.last as ToolMessage;
        expect(toolMessage.content, result);
        expect(agent.state.messages.last.content, 'Sunny in Lima');
      });

      test('closes calls to unregistered tools as unavailable', () async {
        queueRun(toolCallRun(threadId()));

        await runner.run(agent);

        expect(sentInputs(), hasLength(1));
        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, 'Tool is not available.');
        expect(agent.state.messages.last, isA<ToolMessage>());
      });

      test('closes unregistered calls before running again', () async {
        registerTool(weatherTool((_, {required signal}) async => 'ok'));
        queueRun(
          toolCallRun(threadId())..insertAll(4, const [
            ToolCallStartEvent(
              toolCallId: 'c2',
              toolCallName: 'gone',
              parentMessageId: 'a1',
            ),
            ToolCallEndEvent(toolCallId: 'c2'),
          ]),
        );
        queueRun(replyRun(threadId()));

        await runner.run(agent);

        final results = {
          for (final message
              in sentInputs().last.messages.whereType<ToolMessage>())
            message.toolCallId: message.content,
        };
        expect(results, {'c1': 'ok', 'c2': 'Tool is not available.'});
      });

      test('does not run handlers for calls the runtime completed', () async {
        registerRecordingTool();
        queueRun(
          toolCallRun(threadId())..insert(
            4,
            const ToolCallResultEvent(
              messageId: 't1',
              toolCallId: 'c1',
              content: 'from server',
            ),
          ),
        );

        await runner.run(agent);

        expect(called, isFalse);
        expect(sentInputs(), hasLength(1));
        expect(agent.state.toolCalls.single.result, 'from server');
      });

      test('does not run handlers when the run fails', () async {
        registerRecordingTool();
        queueRun(
          toolCallRun(threadId())
            ..[4] = const RunErrorEvent(message: 'model error'),
        );

        await runner.run(agent);

        expect(called, isFalse);
        expect(sentInputs(), hasLength(1));
      });

      test('ignores a run while handlers are running', () async {
        handlerDone = Completer<String>();
        registerTool(weatherTool((_, {required signal}) => handlerDone.future));
        queueToolCallAndReply();

        final run = runner.run(agent);
        await pumpEventQueue();

        await runner.run(agent);
        handlerDone.complete('ok');
        await run;

        expect(sentInputs(), hasLength(2));
      });

      group('a failed run closes open calls', () {
        void expectClosedAsFailed() {
          final view = agent.state.toolCalls.single;
          expect(view.status, ToolCallStatus.complete);
          expect(view.result, 'Tool call failed: the run ended early.');
          final message = agent.state.messages.whereType<ToolMessage>().single;
          expect(message.toolCallId, 'c1');
          expect(message.content, view.result);
        }

        test('when the connection drops after the call ended', () async {
          registerTool(weatherTool((_, {required signal}) async => ''));
          queueRun(toolCallRun(threadId())..removeLast());

          await runner.run(agent);

          expect(sentInputs(), hasLength(1));
          expectClosedAsFailed();
        });

        test('when the runtime reports an error mid-args', () async {
          queueRun([
            ...toolCallRun(threadId()).take(3),
            const RunErrorEvent(message: 'model error'),
          ]);

          await runner.run(agent);

          expectClosedAsFailed();
        });

        test('so the next run sends a valid conversation', () async {
          queueRun(toolCallRun(threadId())..removeLast());
          queueRun(replyRun(threadId()));

          await runner.run(agent);
          await runner.run(agent);

          expect(sentInputs().last.messages.last, isA<ToolMessage>());
        });
      });

      group('stop', () {
        late CancellationSignal handlerSignal;

        test(
          'while the handler runs cancels its signal and does not run again',
          () async {
            handlerDone = Completer<String>();
            registerTool(
              weatherTool((_, {required signal}) {
                handlerSignal = signal;
                return handlerDone.future;
              }),
            );
            queueRun(toolCallRun(threadId()));

            final run = runner.run(agent);
            await pumpEventQueue();

            await runner.stop(agent);
            handlerDone.complete('late result');
            await run;

            expect(handlerSignal.isCancelled, isTrue);
            expect(sentInputs(), hasLength(1));
            expect(agent.state.isRunning, isFalse);
            final view = agent.state.toolCalls.single;
            expect(view.status, ToolCallStatus.complete);
            expect(view.result, 'Tool call cancelled.');
            expect(
              agent.state.messages.whereType<ToolMessage>().single.content,
              'Tool call cancelled.',
            );
            transport.verifyNoStop();
          },
        );

        test('while args stream closes the call as cancelled', () async {
          final events = StreamController<BaseEvent>();
          runs.add(events.stream);
          final run = runner.run(agent);
          events
            ..add(RunStartedEvent(threadId: threadId(), runId: 'r1'))
            ..add(
              const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
            )
            ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'));
          await pumpEventQueue();

          await runner.stop(agent);
          await run;

          expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
          expect(agent.state.messages.last, isA<ToolMessage>());
        });
      });

      group('recorded fixtures', () {
        late List<JsonObject> calls;

        test('runs the handler and sends its result in the next run', () async {
          calls = [];
          registerTool(
            weatherTool((args, {required signal}) async {
              calls.add(args);
              return 'Sunny, 24°C';
            }),
          );
          queueRun(loadFixture('frontend_tool_call').events);
          queueRun(loadFixture('text_stream').events);

          await runner.run(agent);

          expect(calls, [
            const JsonObject({'city': 'Lima'}),
          ]);
          final result = sentInputs().last.messages.whereType<ToolMessage>();
          expect(result.single.content, 'Sunny, 24°C');
          expect(
            agent.state.messages.last.content,
            'Hello! Wonderful to meet you.',
          );
          expect(errors, isEmpty);
        });

        test('leaves backend tool calls with a runtime result alone', () async {
          queueRun(loadFixture('state_snapshot_delta').events);

          await runner.run(agent);

          final call = agent.state.toolCalls.single;
          expect(call.name, 'AGUISendStateDelta');
          expect(call.status, ToolCallStatus.complete);
          expect(call.result, contains('"success":true'));
          expect(sentInputs(), hasLength(1));
          expect(errors, isEmpty);
        });
      });
    });

    group('human-in-the-loop tools', () {
      late HumanInTheLoopTool<JsonObject> tool;
      late Future<void> run;
      late CopilotAgentState waiting;
      // The inputs of every run, read once: the mock counts a verified call
      // only once.
      List<RunAgentInput>? inputs;

      setUp(() {
        tool = approvalTool();
        inputs = null;
        harness.tools.register(tool);
      });

      List<RunAgentInput> sentHumanInputs() => inputs ??= sentInputs();

      /// Queues a run that calls the tool for each of [ids], then a reply.
      void queueCallsAndReply({List<String> ids = const ['c1']}) {
        queueRun(approvalRun(threadId(), ids: ids));
        queueRun(replyRun(threadId()));
      }

      /// Starts the turn and waits until it is blocked on the user.
      Future<void> startRun() async {
        run = runner.run(agent);
        await pumpEventQueue();
        waiting = agent.state;
      }

      /// The tool messages of the conversation sent with the last run, by
      /// call.
      Map<String, String> sentResults() => {
        for (final message
            in sentHumanInputs().last.messages.whereType<ToolMessage>())
          message.toolCallId: message.content,
      };

      test(
        'marks the call as awaiting while the agent stays running',
        () async {
          queueCallsAndReply();

          await startRun();
          runner.respond('c1', 'ok');
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
        runner.respond('c1', 'approved');
        await run;

        expect(sentHumanInputs(), hasLength(2));
        expect(sentResults(), {'c1': 'approved'});
        final call = agent.state.toolCalls.single;
        expect(call.status, ToolCallStatus.complete);
        expect(call.result, 'approved');
        expect(call.awaitingResponse, isFalse);
        expect(agent.state.awaitingResponseIds, isEmpty);
        expect(agent.state.messages.last.content, 'Sunny in Lima');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      test('JSON-encodes an answer that is not a string', () async {
        queueCallsAndReply();

        await startRun();
        runner.respond('c1', {'decision': 'approve', 'count': 2});
        await run;

        expect(sentResults(), {'c1': '{"decision":"approve","count":2}'});
      });

      group('an answer that arrives before the turn waits for the call', () {
        late StreamController<BaseEvent> events;

        setUp(() {
          events = StreamController<BaseEvent>();
          runs.add(events.stream);
          queueRun(replyRun(threadId()));
        });

        test('is kept until the run has finished streaming', () async {
          run = runner.run(agent);
          events.add(RunStartedEvent(threadId: threadId(), runId: 'r1'));
          approvalCall('c1').forEach(events.add);
          await pumpEventQueue();
          // The call is complete, but the run has not finished: the turn
          // doesn't wait for it yet.
          expect(agent.state.awaitingResponseIds, isEmpty);

          runner.respond('c1', 'early');
          events.add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await run;

          expect(sentResults(), {'c1': 'early'});
        });

        test('is ignored while the arguments still stream', () async {
          run = runner.run(agent);
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

          runner.respond('c1', 'too early');
          events
            ..add(
              const ToolCallArgsEvent(toolCallId: 'c1', delta: 'ion": "x"}'),
            )
            ..add(const ToolCallEndEvent(toolCallId: 'c1'))
            ..add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await pumpEventQueue();
          waiting = agent.state;
          runner.respond('c1', 'on time');
          await run;

          expect(waiting.awaitingResponseIds, ['c1']);
          expect(sentResults(), {'c1': 'on time'});
        });
      });

      test(
        'stop while awaiting answers the call as cancelled and ends the turn',
        () async {
          queueRun(approvalRun(threadId()));

          await startRun();
          await runner.stop(agent);
          await run;

          expect(sentHumanInputs(), hasLength(1));
          final call = agent.state.toolCalls.single;
          expect(call.status, ToolCallStatus.complete);
          expect(call.result, 'Tool call cancelled.');
          expect(call.awaitingResponse, isFalse);
          expect(agent.state.isRunning, isFalse);
          transport.verifyNoStop();
        },
      );

      test('an answer after a stop is ignored', () async {
        queueRun(approvalRun(threadId()));

        await startRun();
        await runner.stop(agent);
        await run;
        runner.respond('c1', 'too late');

        expect(agent.state.toolCalls.single.result, 'Tool call cancelled.');
        expect(agent.state.messages.whereType<ToolMessage>(), hasLength(1));
      });

      test('close while awaiting ends the turn', () async {
        queueRun(approvalRun(threadId()));

        await startRun();
        await runner.close();
        await run;

        expect(sentHumanInputs(), hasLength(1));
      });

      test(
        'two calls wait together and can be answered out of order',
        () async {
          queueCallsAndReply(ids: const ['c1', 'c2']);

          await startRun();
          runner.respond('c2', 'second');
          await pumpEventQueue();
          final mid = agent.state.awaitingResponseIds;
          runner.respond('c1', 'first');
          await run;

          expect(waiting.awaitingResponseIds, ['c1', 'c2']);
          expect(mid, ['c1', 'c2']);
          expect(sentResults(), {'c1': 'first', 'c2': 'second'});
          final messages = sentHumanInputs().last.messages;
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
          runner
            ..respond('missing', 'nobody asked')
            ..respond('c1', 'first')
            ..respond('c1', 'second');
          await run;
          runner.respond('c1', 'third');

          expect(sentResults(), {'c1': 'first'});
          expect(agent.state.toolCalls.single.result, 'first');
          expect(errors, isEmpty);
        },
      );

      test('ignores an answer for a call of a frontend tool', () async {
        harness.tools.register(
          weatherTool((_, {required signal}) async => 'sunny'),
        );
        queueRun(toolCallRun(threadId()));
        queueRun(replyRun(threadId()));

        run = runner.run(agent);
        await pumpEventQueue();
        runner.respond('c1', 'not for you');
        await run;

        expect(sentResults(), {'c1': 'sunny'});
      });

      test('an answer that cannot be encoded is reported and the call keeps '
          'waiting', () async {
        queueCallsAndReply();

        await startRun();
        runner.respond('c1', DateTime(2026));
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        runner.respond('c1', 'fine');
        await run;

        expect(errors.single, isA<JsonUnsupportedObjectError>());
        expect(mid, ['c1']);
        expect(sentResults(), {'c1': 'fine'});
      });

      group('cancelAwaiting', () {
        test('answers the waiting calls as cancelled and continues', () async {
          queueCallsAndReply();

          await startRun();
          runner.cancelAwaiting(tool.name);
          await run;

          expect(sentHumanInputs(), hasLength(2));
          expect(sentResults(), {'c1': 'Tool call cancelled.'});
          expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
          expect(agent.state.isRunning, isFalse);
        });

        test('leaves the calls of other tools alone', () async {
          queueCallsAndReply();

          await startRun();
          runner
            ..cancelAwaiting('other')
            ..respond('c1', 'ok');
          await run;

          expect(sentResults(), {'c1': 'ok'});
        });
      });

      test(
        'closes a call of an unregistered tool as unavailable without waiting',
        () async {
          harness.tools.unregister(tool);
          queueRun(approvalRun(threadId()));
          queueRun(replyRun(threadId()));

          await runner.run(agent);

          final call = agent.state.toolCalls.single;
          expect(call.result, 'Tool is not available.');
          expect(call.awaitingResponse, isFalse);
        },
      );

      test(
        'answers arguments that do not match the schema without waiting',
        () async {
          queueRun(approvalRun(threadId(), args: '{"action": 1}'));
          queueRun(replyRun(threadId()));

          await runner.run(agent);

          expect(sentResults()['c1'], contains("arguments don't match"));
          expect(agent.state.awaitingResponseIds, isEmpty);
        },
      );

      group('followUp', () {
        test('false ends the turn without another run', () async {
          tool = approvalTool(followUp: false);
          harness.tools.register(tool);
          queueRun(approvalRun(threadId()));

          await startRun();
          runner.respond('c1', 'noted');
          await run;

          expect(sentHumanInputs(), hasLength(1));
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
            harness.tools
              ..register(approvalTool(followUp: false))
              ..register(weatherTool((_, {required signal}) async => 'sunny'));
            queueRun([
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
            ]);
            queueRun(replyRun(threadId()));

            await startRun();
            runner.respond('c1', 'noted');
            await run;

            expect(sentHumanInputs(), hasLength(2));
            expect(sentResults(), {'c1': 'noted', 'c2': 'sunny'});
          },
        );
      });

      test('isRunning stays true until the end of the turn', () async {
        queueCallsAndReply();
        final running = recordRunning();

        await startRun();
        runner.respond('c1', 'ok');
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
