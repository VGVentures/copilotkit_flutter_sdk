import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient human-in-the-loop tools', () {
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
      for (final message in sentInputs().last.messages.whereType<ToolMessage>())
        message.toolCallId: message.content,
    };

    test('marks the call as awaiting while the agent stays running', () async {
      queueCallsAndReply();

      await startRun();
      client.respondToToolCall('c1', 'ok');
      await run;

      final call = waiting.toolCalls.single;
      expect(call.status, ToolCallStatus.executing);
      expect(call.awaitingResponse, isTrue);
      expect(waiting.awaitingResponseIds, ['c1']);
      expect(waiting.isRunning, isTrue);
    });

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
          ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: 'ion": "x"}'))
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

    test('two calls wait together and can be answered out of order', () async {
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
    });

    test('ignores a duplicate answer and answers for unknown calls', () async {
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
    });

    test('ignores an answer for a call of a frontend tool', () async {
      client.registerTool(weatherTool((_, {required signal}) async => 'sunny'));
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

      test('keeps the call waiting when the tool was replaced first', () async {
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
      });

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
            Stream.fromIterable(approvalRun(threadId(), args: '{"action": 1}')),
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
}
