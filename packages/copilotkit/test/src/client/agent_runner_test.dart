import 'dart:async';

import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
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

  group(AgentRunner, () {
    late RunnerHarness harness;
    late AgentRunner runner;
    late MockAgentTransport transport;
    late CopilotAgent agent;
    late List<Stream<ag_ui.BaseEvent>> runs;
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

    List<ag_ui.RunAgentInput> sentInputs() => transport.sentInputs();

    void queueRun(List<ag_ui.BaseEvent> events) =>
        runs.add(Stream.fromIterable(events));

    /// Records whether the agent was running on every state it emits.
    List<bool> recordRunning() {
      final running = <bool>[];
      agent.stream.listen((state) => running.add(state.isRunning));
      return running;
    }

    group('run', () {
      const message = UserMessage(id: 'u1', content: 'Hi');

      test('appends the given message before the run', () async {
        runs.add(const Stream.empty());

        await runner.run(agent, message: message);

        expect(sentInputs().single.messages.map(Message.fromAgUi), [message]);
        expect(agent.state.messages, [message]);
      });

      late StreamController<ag_ui.BaseEvent> events;

      test(
        'drops the given message when the agent is already running',
        () async {
          events = StreamController<ag_ui.BaseEvent>();
          runs.add(events.stream);
          final first = runner.run(agent);
          await pumpEventQueue();

          await runner.run(agent, message: message);

          events.add(ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'));
          await events.close();
          await first;
          expect(agent.state.messages, isEmpty);
        },
      );

      test('is running as soon as the run starts', () async {
        events = StreamController<ag_ui.BaseEvent>();
        runs.add(events.stream);

        final run = runner.run(agent);
        await pumpEventQueue();
        expect(agent.state.isRunning, isTrue);

        events.add(ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'));
        await events.close();
        await run;
        expect(agent.state.isRunning, isFalse);
      });

      test('ignores a run while one is in progress', () async {
        events = StreamController<ag_ui.BaseEvent>();
        runs.add(events.stream);
        final first = runner.run(agent);
        await pumpEventQueue();

        await runner.run(agent);

        events.add(ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r'));
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
    });

    group('stop', () {
      late StreamController<ag_ui.BaseEvent> events;
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
        events = StreamController<ag_ui.BaseEvent>(
          onCancel: () => cancelled = true,
        );
        useStreamingHarness();
      });

      Future<void> startStreaming() async {
        run = runner.run(agent);
        events
          ..add(ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r'))
          ..add(const ag_ui.TextMessageStartEvent(messageId: 'm1'))
          ..add(
            const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'Hal'),
          );
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
          expect(textOf(agent.state.messages.single), 'Hal');
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

        events.add(
          const ag_ui.TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
        );
        await pumpEventQueue();

        expect(changes, isEmpty);
        expect(textOf(agent.state.messages.single), 'Hal');
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
        (
          'fails',
          (StreamController<ag_ui.BaseEvent> e) => e.addError(Exception()),
        ),
        ('ends early', (StreamController<ag_ui.BaseEvent> e) => e.close()),
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
            ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r2'),
            const ag_ui.TextMessageStartEvent(messageId: 'm2'),
            const ag_ui.TextMessageContentEvent(
              messageId: 'm2',
              delta: 'Again',
            ),
            ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r2'),
          ]),
        );

        await runner.run(agent);

        expect(agent.state.isRunning, isFalse);
        expect(agent.state.messages.map(textOf), ['Hal', 'Again']);
      });

      test('stops one agent while another keeps running', () async {
        final otherEvents = StreamController<ag_ui.BaseEvent>();
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
          ..add(
            ag_ui.RunStartedEvent(threadId: other.state.threadId, runId: 'o'),
          )
          ..add(
            ag_ui.RunFinishedEvent(threadId: other.state.threadId, runId: 'o'),
          );
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
          StreamController<ag_ui.BaseEvent>(onCancel: () => cancelled = true)
              .stream,
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

      Map<String, Object?>? receivedArgs;
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

        expect(receivedArgs, const {'city': 'Lima'});
        expect(receivedSignal!.isCancelled, isFalse);
        final inputs = sentInputs();
        expect(inputs, hasLength(2));
        final followUp = inputs.last.messages;
        final assistant =
            followUp[followUp.length - 2] as ag_ui.AssistantMessage;
        expect(
          assistant.toolCalls!.single.function.arguments,
          '{"city": "Lima"}',
        );
        final toolMessage = followUp.last as ag_ui.ToolMessage;
        expect(Uuid.isValidUUID(fromString: toolMessage.id!), isTrue);
        expect(toolMessage.toolCallId, 'c1');
        expect(toolMessage.content, '{"forecast": "sunny"}');
        expect(agent.state.toolCalls.single.result, '{"forecast": "sunny"}');
        expect(statuses, [
          ToolCallStatus.inProgress,
          ToolCallStatus.executing,
          ToolCallStatus.complete,
        ]);
        expect(textOf(agent.state.messages.last), 'Sunny in Lima');
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
          ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r1'),
          const ag_ui.RunErrorEvent(message: 'model error'),
        ]);
        running = recordRunning();

        await runner.run(agent);
        // The stream delivers the last state after the turn completes.
        await pumpEventQueue();

        expect(running.last, isFalse);
        expect(running.sublist(0, running.length - 1), everyElement(isTrue));
        expect(errors, hasLength(1));
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

      test('does not run handlers when the run fails', () async {
        registerRecordingTool();
        queueRun(
          toolCallRun(threadId())
            ..[4] = const ag_ui.RunErrorEvent(message: 'model error'),
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
            const ag_ui.RunErrorEvent(message: 'model error'),
          ]);

          await runner.run(agent);

          expectClosedAsFailed();
        });

        test('so the next run sends a valid conversation', () async {
          queueRun(toolCallRun(threadId())..removeLast());
          queueRun(replyRun(threadId()));

          await runner.run(agent);
          await runner.run(agent);

          expect(sentInputs().last.messages.last, isA<ag_ui.ToolMessage>());
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
          final events = StreamController<ag_ui.BaseEvent>();
          runs.add(events.stream);
          final run = runner.run(agent);
          events
            ..add(ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r1'))
            ..add(
              const ag_ui.ToolCallStartEvent(
                toolCallId: 'c1',
                toolCallName: 'tool',
              ),
            )
            ..add(
              const ag_ui.ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'),
            );
          await pumpEventQueue();

          await runner.stop(agent);
          await run;

          expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
          expect(agent.state.messages.last, isA<ToolMessage>());
        });
      });

      group('recorded fixtures', () {
        late List<Map<String, Object?>> calls;

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
            const {'city': 'Lima'},
          ]);
          final result = sentInputs().last.messages
              .whereType<ag_ui.ToolMessage>();
          expect(result.single.content, 'Sunny, 24°C');
          expect(
            textOf(agent.state.messages.last),
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
      late HumanInTheLoopTool<Map<String, Object?>> tool;
      late Future<void> run;
      late CopilotAgentState waiting;
      // The inputs of every run, read once: the mock counts a verified call
      // only once.
      List<ag_ui.RunAgentInput>? inputs;

      setUp(() {
        tool = approvalTool();
        inputs = null;
        harness.tools.register(tool);
      });

      List<ag_ui.RunAgentInput> sentHumanInputs() => inputs ??= sentInputs();

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
            in sentHumanInputs().last.messages.whereType<ag_ui.ToolMessage>())
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
        expect(textOf(agent.state.messages.last), 'Sunny in Lima');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      });

      group('an answer that arrives before the turn waits for the call', () {
        late StreamController<ag_ui.BaseEvent> events;

        setUp(() {
          events = StreamController<ag_ui.BaseEvent>();
          runs.add(events.stream);
          queueRun(replyRun(threadId()));
        });

        test('is kept until the run has finished streaming', () async {
          run = runner.run(agent);
          events.add(ag_ui.RunStartedEvent(threadId: threadId(), runId: 'r1'));
          approvalCall('c1').forEach(events.add);
          await pumpEventQueue();
          // The call is complete, but the run has not finished: the turn
          // doesn't wait for it yet.
          expect(agent.state.awaitingResponseIds, isEmpty);

          runner.respond('c1', 'early');
          events.add(ag_ui.RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await run;

          expect(sentResults(), {'c1': 'early'});
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
      });

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
