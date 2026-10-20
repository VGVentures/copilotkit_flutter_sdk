import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/client.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/tool_runs.dart';

void main() {
  group(ToolCallRunner, () {
    late ToolRegistry tools;
    late List<Object> errors;
    late ToolCallRunner toolCalls;
    late CopilotKitAgent agent;
    late Turn turn;

    setUp(() {
      tools = ToolRegistry();
      errors = [];
      toolCalls = ToolCallRunner(
        tools: tools,
        onError: (error, _) => errors.add(error),
      );
      agent = CopilotKitAgent(agentId: 'default');
      turn = Turn(agent);
    });

    String threadId() => agent.state.threadId;

    /// Applies [events] to the agent, as a run would.
    void receive(List<BaseEvent> events) => events.forEach(agent.apply);

    /// The results of the agent's tool calls, by call.
    Map<String, String?> results() => {
      for (final call in agent.state.toolCalls) call.id: call.result,
    };

    group('runPending', () {
      test('runs the handler and adds its result', () async {
        JsonObject? receivedArgs;
        CancellationSignal? receivedSignal;
        tools.register(
          weatherTool((args, {required signal}) async {
            receivedArgs = args;
            receivedSignal = signal;
            return 'sunny';
          }),
        );
        receive(toolCallRun(threadId()));

        expect(await toolCalls.runPending(turn), isTrue);
        expect(receivedArgs, const JsonObject({'city': 'Lima'}));
        expect(receivedSignal, same(turn.signal));
        final message = agent.state.messages.last as ToolMessage;
        expect(Uuid.isValidUUID(fromString: message.id!), isTrue);
        expect(message.toolCallId, 'c1');
        expect(message.content, 'sunny');
        expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
        expect(errors, isEmpty);
      });

      test('passes the handler the args parsed by the schema', () async {
        JsonObject? receivedArgs;
        tools.register(
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
        receive(toolCallRun(threadId()));

        await toolCalls.runPending(turn);

        expect(receivedArgs, const JsonObject({'city': 'Lima', 'days': 3}));
      });

      final failure = Exception('no network');

      test(
        'turns handler errors into a generic result and reports them',
        () async {
          tools.register(
            weatherTool((_, {required signal}) async => throw failure),
          );
          receive(toolCallRun(threadId()));

          expect(await toolCalls.runPending(turn), isTrue);
          expect(errors, [same(failure)]);
          expect(results(), {'c1': 'Tool failed.'});
        },
      );

      test('answers invalid args without running the handler', () async {
        var called = false;
        tools.register(
          weatherTool((_, {required signal}) async {
            called = true;
            return '';
          }),
        );
        receive(
          toolCallRun(threadId())
            ..[2] = const ToolCallArgsEvent(
              toolCallId: 'c1',
              delta: '{"days": "3"}',
            ),
        );

        expect(await toolCalls.runPending(turn), isTrue);
        expect(called, isFalse);
        expect(errors, isEmpty);
        expect(
          agent.state.toolCalls.single.result,
          allOf(
            startsWith("The tool didn't run"),
            contains('- city: Required property "city" is missing.'),
            contains('- days: Expected integer, got string.'),
          ),
        );
      });

      test('closes calls to unregistered tools as unavailable', () async {
        receive(toolCallRun(threadId()));

        expect(await toolCalls.runPending(turn), isFalse);
        expect(results(), {'c1': 'Tool is not available.'});
        expect(agent.state.messages.last, isA<ToolMessage>());
      });

      test('closes unregistered calls next to registered ones', () async {
        tools.register(weatherTool((_, {required signal}) async => 'ok'));
        receive(
          toolCallRun(threadId())..insertAll(4, const [
            ToolCallStartEvent(
              toolCallId: 'c2',
              toolCallName: 'gone',
              parentMessageId: 'a1',
            ),
            ToolCallEndEvent(toolCallId: 'c2'),
          ]),
        );

        expect(await toolCalls.runPending(turn), isTrue);
        expect(results(), {'c1': 'ok', 'c2': 'Tool is not available.'});
      });

      test('does not run handlers for calls the runtime completed', () async {
        var called = false;
        tools.register(
          weatherTool((_, {required signal}) async {
            called = true;
            return '';
          }),
        );
        receive(
          toolCallRun(threadId())..insert(
            4,
            const ToolCallResultEvent(
              messageId: 't1',
              toolCallId: 'c1',
              content: 'from server',
            ),
          ),
        );

        expect(await toolCalls.runPending(turn), isFalse);
        expect(called, isFalse);
        expect(results(), {'c1': 'from server'});
      });

      test('adds no result once the turn is stopped', () async {
        final handlerDone = Completer<String>();
        tools.register(
          weatherTool((_, {required signal}) => handlerDone.future),
        );
        receive(toolCallRun(threadId()));

        final again = toolCalls.runPending(turn);
        await pumpEventQueue();
        turn.signal.cancel();
        handlerDone.complete('late result');

        expect(await again, isFalse);
        expect(results(), {'c1': null});
      });
    });

    group('closeOpen', () {
      setUp(
        () => receive([
          ...approvalCall('c1'),
          ...approvalCall('c2'),
          const ToolCallResultEvent(
            messageId: 't3',
            toolCallId: 'c2',
            content: 'done',
          ),
        ]),
      );

      test('gives every open call the result', () {
        toolCalls.closeOpen(agent, FallbackToolResult.failed);

        expect(results(), {
          'c1': 'Tool call failed: the run ended early.',
          'c2': 'done',
        });
      });

      test('only gives the result to the calls that match where', () {
        toolCalls.closeOpen(
          agent,
          FallbackToolResult.cancelled,
          where: (call) => call.id == 'other',
        );

        expect(results(), {'c1': null, 'c2': 'done'});
      });
    });

    group('human-in-the-loop tools', () {
      late HumanInTheLoopTool<JsonObject> tool;

      setUp(() {
        tool = approvalTool();
        tools.register(tool);
      });

      /// Receives a run that calls the tool for each of [ids] and starts
      /// waiting for them; returns what `runPending` returns.
      Future<bool> wait({List<String> ids = const ['c1']}) {
        receive(approvalRun(threadId(), ids: ids));
        return toolCalls.runPending(turn);
      }

      void respond(String toolCallId, Object? result) =>
          toolCalls.respond([agent], toolCallId, result);

      test('marks the calls as awaiting a response', () async {
        final again = wait(ids: const ['c1', 'c2']);
        await pumpEventQueue();

        expect(agent.state.awaitingResponseIds, ['c1', 'c2']);
        expect(
          agent.state.toolCalls.map((call) => call.status),
          everyElement(ToolCallStatus.executing),
        );

        respond('c1', 'a');
        respond('c2', 'b');
        expect(await again, isTrue);
      });

      test('adds the answer as the result', () async {
        final again = wait();
        await pumpEventQueue();

        respond('c1', 'approved');

        expect(await again, isTrue);
        final call = agent.state.toolCalls.single;
        expect(call.status, ToolCallStatus.complete);
        expect(call.result, 'approved');
        expect(call.awaitingResponse, isFalse);
        expect(errors, isEmpty);
      });

      test('JSON-encodes an answer that is not a string', () async {
        final again = wait();
        await pumpEventQueue();

        respond('c1', {'decision': 'approve', 'count': 2});
        await again;

        expect(results(), {'c1': '{"decision":"approve","count":2}'});
      });

      test('two calls can be answered out of order', () async {
        final again = wait(ids: const ['c1', 'c2']);
        await pumpEventQueue();

        respond('c2', 'second');
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        respond('c1', 'first');
        await again;

        expect(mid, ['c1', 'c2']);
        expect(results(), {'c1': 'first', 'c2': 'second'});
        expect(
          agent.state.messages.whereType<ToolMessage>().map(
            (m) => m.toolCallId,
          ),
          ['c1', 'c2'],
        );
      });

      test(
        'ignores a duplicate answer and answers for unknown calls',
        () async {
          final again = wait();
          await pumpEventQueue();

          respond('missing', 'nobody asked');
          respond('c1', 'first');
          respond('c1', 'second');
          await again;
          respond('c1', 'third');

          expect(results(), {'c1': 'first'});
          expect(errors, isEmpty);
        },
      );

      test('ignores an answer for a call of an agent not given', () async {
        final again = wait();
        await pumpEventQueue();

        toolCalls.respond(const [], 'c1', 'not in a turn');
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        respond('c1', 'ok');
        await again;

        expect(mid, ['c1']);
        expect(results(), {'c1': 'ok'});
      });

      test('ignores an answer for a call of a frontend tool', () async {
        tools.register(weatherTool((_, {required signal}) async => 'sunny'));
        receive(toolCallRun(threadId()));

        respond('c1', 'not for you');
        await toolCalls.runPending(turn);

        expect(results(), {'c1': 'sunny'});
      });

      test(
        'reports an answer that cannot be encoded and keeps waiting',
        () async {
          final again = wait();
          await pumpEventQueue();

          respond('c1', DateTime(2026));
          await pumpEventQueue();
          final mid = agent.state.awaitingResponseIds;
          respond('c1', 'fine');
          await again;

          expect(errors.single, isA<JsonUnsupportedObjectError>());
          expect(mid, ['c1']);
          expect(results(), {'c1': 'fine'});
        },
      );

      test('keeps an answer that arrives before the wait', () async {
        receive(approvalRun(threadId()));

        respond('c1', 'early');

        expect(await toolCalls.runPending(turn), isTrue);
        expect(results(), {'c1': 'early'});
      });

      test('ignores an answer while the arguments still stream', () async {
        receive(approvalCall('c1').sublist(0, 1));

        respond('c1', 'too early');
        receive([
          const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"action": "x"}'),
          const ToolCallEndEvent(toolCallId: 'c1'),
        ]);
        final again = toolCalls.runPending(turn);
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        respond('c1', 'on time');
        await again;

        expect(mid, ['c1']);
        expect(results(), {'c1': 'on time'});
      });

      test('a stopped turn ends the wait without a result', () async {
        final again = wait();
        await pumpEventQueue();

        turn.signal.cancel();

        expect(await again, isFalse);
        expect(results(), {'c1': null});
      });

      test('clear forgets an answer that arrived early', () async {
        receive(approvalRun(threadId()));
        respond('c1', 'early');

        toolCalls.clear();
        final again = toolCalls.runPending(turn);
        await pumpEventQueue();

        expect(agent.state.awaitingResponseIds, ['c1']);
        respond('c1', 'later');
        await again;
        expect(results(), {'c1': 'later'});
      });

      group('cancelAwaiting', () {
        test('answers the waiting calls as cancelled', () async {
          final again = wait();
          await pumpEventQueue();

          toolCalls.cancelAwaiting([agent], tool.name);

          expect(await again, isTrue);
          expect(results(), {'c1': 'Tool call cancelled.'});
          expect(agent.state.toolCalls.single.awaitingResponse, isFalse);
        });

        test('leaves the calls of other tools alone', () async {
          final again = wait();
          await pumpEventQueue();

          toolCalls.cancelAwaiting([agent], 'other');
          respond('c1', 'ok');
          await again;

          expect(results(), {'c1': 'ok'});
        });
      });

      test('answers arguments that do not match without waiting', () async {
        receive(approvalRun(threadId(), args: '{"action": 1}'));

        expect(await toolCalls.runPending(turn), isTrue);
        expect(results()['c1'], contains("arguments don't match"));
        expect(agent.state.awaitingResponseIds, isEmpty);
      });

      group('followUp', () {
        test('false returns false once answered', () async {
          tools.register(approvalTool(followUp: false));
          final again = wait();
          await pumpEventQueue();

          respond('c1', 'noted');

          expect(await again, isFalse);
          expect(results(), {'c1': 'noted'});
        });

        test('false still returns true when another call follows up', () async {
          tools
            ..register(approvalTool(followUp: false))
            ..register(weatherTool((_, {required signal}) async => 'sunny'));
          receive([
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
          ]);
          final again = toolCalls.runPending(turn);
          await pumpEventQueue();

          respond('c1', 'noted');

          expect(await again, isTrue);
          expect(results(), {'c1': 'noted', 'c2': 'sunny'});
        });
      });
    });
  });
}
