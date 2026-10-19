import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';
import '../../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('human-in-the-loop tools', () {
    late ToolLoopHarness harness;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;
    late List<Stream<BaseEvent>> runs;
    late HumanInTheLoopTool tool;
    late Future<void> run;
    late CopilotAgentState waiting;
    late List<String> mid;
    // The inputs of every run, read once: the mock counts a verified call
    // only once.
    List<RunAgentInput>? inputs;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      tool = approvalTool();
      inputs = null;
      await client.registerTool(tool);
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
      run = client.runAgent(agent);
      await pumpEventQueue();
      waiting = agent.state;
    }

    /// The tool messages of the conversation sent with the last run, by call.
    Map<String, String> sentResults() => {
      for (final message in sentInputs().last.messages.whereType<ToolMessage>())
        message.toolCallId: message.content,
    };

    blocTest<CopilotKitBloc, CopilotKitState>(
      'marks the call as awaiting while the agent stays running',
      setUp: queueCallsAndReply,
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('c1', 'ok');
        await run;
      },
      verify: (_) {
        final call = waiting.toolCalls.single;
        expect(call.status, ToolCallStatus.executing);
        expect(call.awaitingResponse, isTrue);
        expect(waiting.awaitingResponseIds, ['c1']);
        expect(waiting.isRunning, isTrue);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'sends the answer as the tool result and runs again',
      setUp: queueCallsAndReply,
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('c1', 'approved');
        await run;
      },
      verify: (_) {
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
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'JSON-encodes an answer that is not a string',
      setUp: queueCallsAndReply,
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('c1', {'decision': 'approve', 'count': 2});
        await run;
      },
      verify: (_) =>
          expect(sentResults(), {'c1': '{"decision":"approve","count":2}'}),
    );

    group('an answer that arrives before the turn waits for the call', () {
      late StreamController<BaseEvent> events;

      setUp(() {
        events = StreamController<BaseEvent>();
        runs
          ..add(events.stream)
          ..add(Stream.fromIterable(replyRun(threadId())));
      });

      blocTest<CopilotKitBloc, CopilotKitState>(
        'is kept until the run has finished streaming',
        build: () => client,
        act: (_) async {
          run = client.runAgent(agent);
          events.add(RunStartedEvent(threadId: threadId(), runId: 'r1'));
          approvalCall('c1').forEach(events.add);
          await pumpEventQueue();
          // The call is complete, but the run has not finished: the turn
          // doesn't wait for it yet.
          expect(agent.state.awaitingResponseIds, isEmpty);

          await client.respond('c1', 'early');
          events.add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await run;
        },
        verify: (_) => expect(sentResults(), {'c1': 'early'}),
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'is ignored while the arguments still stream',
        build: () => client,
        act: (_) async {
          run = client.runAgent(agent);
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

          await client.respond('c1', 'too early');
          events
            ..add(
              const ToolCallArgsEvent(toolCallId: 'c1', delta: 'ion": "x"}'),
            )
            ..add(const ToolCallEndEvent(toolCallId: 'c1'))
            ..add(RunFinishedEvent(threadId: threadId(), runId: 'r1'));
          await events.close();
          await pumpEventQueue();
          waiting = agent.state;
          await client.respond('c1', 'on time');
          await run;
        },
        verify: (_) {
          expect(waiting.awaitingResponseIds, ['c1']);
          expect(sentResults(), {'c1': 'on time'});
        },
      );
    });

    blocTest<CopilotKitBloc, CopilotKitState>(
      'stop while awaiting answers the call as cancelled and ends the turn',
      setUp: () => runs.add(Stream.fromIterable(approvalRun(threadId()))),
      build: () => client,
      act: (_) async {
        await startRun();
        await client.stopAgent(agent);
        await run;
      },
      verify: (_) {
        expect(sentInputs(), hasLength(1));
        final call = agent.state.toolCalls.single;
        expect(call.status, ToolCallStatus.complete);
        expect(call.result, 'Tool call cancelled.');
        expect(call.awaitingResponse, isFalse);
        expect(agent.state.isRunning, isFalse);
        harness.transport.verifyNoStop();
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'an answer after a stop is ignored',
      setUp: () => runs.add(Stream.fromIterable(approvalRun(threadId()))),
      build: () => client,
      act: (_) async {
        await startRun();
        await client.stopAgent(agent);
        await run;
        await client.respond('c1', 'too late');
      },
      verify: (_) {
        expect(agent.state.toolCalls.single.result, 'Tool call cancelled.');
        expect(agent.state.messages.whereType<ToolMessage>(), hasLength(1));
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'closing the client while awaiting ends the turn',
      setUp: () => runs.add(Stream.fromIterable(approvalRun(threadId()))),
      build: () => client,
      act: (_) async {
        await startRun();
        await client.close();
        await run;
      },
      verify: (_) => expect(sentInputs(), hasLength(1)),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'two calls wait together and can be answered out of order',
      setUp: () => queueCallsAndReply(ids: const ['c1', 'c2']),
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('c2', 'second');
        await pumpEventQueue();
        mid = agent.state.awaitingResponseIds;
        await client.respond('c1', 'first');
        await run;
      },
      verify: (_) {
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

    blocTest<CopilotKitBloc, CopilotKitState>(
      'ignores a duplicate answer and answers for unknown calls',
      setUp: queueCallsAndReply,
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('missing', 'nobody asked');
        await client.respond('c1', 'first');
        await client.respond('c1', 'second');
        await run;
        await client.respond('c1', 'third');
      },
      verify: (_) {
        expect(sentResults(), {'c1': 'first'});
        expect(agent.state.toolCalls.single.result, 'first');
        expect(harness.errors, isEmpty);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'ignores an answer for a call that is not human-in-the-loop',
      setUp: () async {
        await client.registerTool(
          weatherTool((_, {required signal}) async => 'sunny'),
        );
        runs
          ..add(Stream.fromIterable(toolCallRun(threadId())))
          ..add(Stream.fromIterable(replyRun(threadId())));
      },
      build: () => client,
      act: (_) async {
        run = client.runAgent(agent);
        await client.respond('c1', 'not for you');
        await run;
      },
      verify: (_) => expect(sentResults(), {'c1': 'sunny'}),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'an answer that cannot be encoded is reported and the call keeps waiting',
      setUp: queueCallsAndReply,
      build: () => client,
      act: (_) async {
        await startRun();
        await client.respond('c1', DateTime(2026));
        await pumpEventQueue();
        mid = agent.state.awaitingResponseIds;
        await client.respond('c1', 'fine');
        await run;
      },
      verify: (_) {
        expect(harness.errors.single, isA<JsonUnsupportedObjectError>());
        expect(mid, ['c1']);
        expect(sentResults(), {'c1': 'fine'});
      },
    );

    group('unregistering the tool while a call waits', () {
      blocTest<CopilotKitBloc, CopilotKitState>(
        'answers the call as cancelled and continues the turn',
        setUp: queueCallsAndReply,
        build: () => client,
        act: (_) async {
          await startRun();
          await client.unregisterTool(tool);
          await run;
        },
        verify: (_) {
          expect(sentInputs(), hasLength(2));
          expect(sentResults(), {'c1': 'Tool call cancelled.'});
          expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
          expect(agent.state.isRunning, isFalse);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'keeps the call waiting when the tool was replaced first',
        setUp: queueCallsAndReply,
        build: () => client,
        act: (_) async {
          await startRun();
          await client.registerTool(
            HumanInTheLoopTool(
              name: tool.name,
              description: 'An updated description',
              parameters: tool.parameters,
            ),
          );
          await client.unregisterTool(tool);
          await pumpEventQueue();
          mid = agent.state.awaitingResponseIds;
          await client.respond('c1', 'still here');
          await run;
        },
        verify: (_) {
          expect(mid, ['c1']);
          expect(sentResults(), {'c1': 'still here'});
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'leaves the calls of other tools alone',
        setUp: queueCallsAndReply,
        build: () => client,
        act: (_) async {
          await startRun();
          await client.unregisterTool(
            HumanInTheLoopTool(
              name: 'other',
              description: 'Another tool',
              parameters: Ack.object({}),
            ),
          );
          await client.respond('c1', 'ok');
          await run;
        },
        verify: (_) => expect(sentResults(), {'c1': 'ok'}),
      );
    });

    blocTest<CopilotKitBloc, CopilotKitState>(
      'closes a call of an unregistered tool as unavailable without waiting',
      setUp: () async {
        await client.unregisterTool(tool);
        runs
          ..add(Stream.fromIterable(approvalRun(threadId())))
          ..add(Stream.fromIterable(replyRun(threadId())));
      },
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        final call = agent.state.toolCalls.single;
        expect(call.result, 'Tool is not available.');
        expect(call.awaitingResponse, isFalse);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'answers arguments that do not match the schema without waiting',
      setUp: () => runs
        ..add(
          Stream.fromIterable(approvalRun(threadId(), args: '{"action": 1}')),
        )
        ..add(Stream.fromIterable(replyRun(threadId()))),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(sentResults()['c1'], contains("arguments don't match"));
        expect(agent.state.awaitingResponseIds, isEmpty);
      },
    );

    group('followUp', () {
      blocTest<CopilotKitBloc, CopilotKitState>(
        'false ends the turn without another run',
        setUp: () async {
          tool = approvalTool(followUp: false);
          await client.registerTool(tool);
          runs.add(Stream.fromIterable(approvalRun(threadId())));
        },
        build: () => client,
        act: (_) async {
          await startRun();
          await client.respond('c1', 'noted');
          await run;
        },
        verify: (_) {
          expect(sentInputs(), hasLength(1));
          final call = agent.state.toolCalls.single;
          expect(call.status, ToolCallStatus.complete);
          expect(call.result, 'noted');
          expect(
            agent.state.messages.whereType<ToolMessage>().single.content,
            'noted',
          );
          expect(agent.state.isRunning, isFalse);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'false still runs again when another call in the turn follows up',
        setUp: () async {
          await client.registerTool(approvalTool(followUp: false));
          await client.registerTool(
            weatherTool((_, {required signal}) async => 'sunny'),
          );
          runs
            ..add(
              Stream.fromIterable([
                RunStartedEvent(threadId: threadId(), runId: 'r1'),
                ...approvalCall('c1'),
                ...toolCallRun(threadId())
                    .sublist(1, 4)
                    .map(
                      (event) => switch (event) {
                        ToolCallStartEvent() => const ToolCallStartEvent(
                          toolCallId: 'c2',
                          toolCallName: 'showWeather',
                          parentMessageId: 'a1',
                        ),
                        ToolCallArgsEvent(:final delta) => ToolCallArgsEvent(
                          toolCallId: 'c2',
                          delta: delta,
                        ),
                        _ => const ToolCallEndEvent(toolCallId: 'c2'),
                      },
                    ),
                RunFinishedEvent(threadId: threadId(), runId: 'r1'),
              ]),
            )
            ..add(Stream.fromIterable(replyRun(threadId())));
        },
        build: () => client,
        act: (_) async {
          await startRun();
          await client.respond('c1', 'noted');
          await run;
        },
        verify: (_) {
          expect(sentInputs(), hasLength(2));
          expect(sentResults(), {'c1': 'noted', 'c2': 'sunny'});
        },
      );
    });

    group('isRunning', () {
      late List<bool> running;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'stays true from the first run to the end of the turn',
        setUp: () {
          queueCallsAndReply();
          running = [];
          agent.stream.listen((state) => running.add(state.isRunning));
        },
        build: () => client,
        act: (_) async {
          await startRun();
          await client.respond('c1', 'ok');
          await run;
        },
        verify: (_) {
          expect(running.first, isTrue);
          expect(running.sublist(0, running.length - 1), everyElement(isTrue));
          expect(running.last, isFalse);
        },
      );
    });
  });
}
