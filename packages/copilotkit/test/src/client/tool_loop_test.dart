import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_x.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgentBloc agent;
    late List<Stream<BaseEvent>> runs;
    late List<Object> errors;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      errors = harness.errors;
    });

    List<RunAgentInput> sentInputs() => harness.transport.sentInputs();

    test('runs the handler, sends the result and runs again', () async {
      Map<String, Object?>? receivedArgs;
      CancellationSignal? receivedSignal;
      await client.registerTool(
        weatherTool((args, {required signal}) async {
          receivedArgs = args;
          receivedSignal = signal;
          return '{"forecast": "sunny"}';
        }),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));
      final statuses = <ToolCallStatus>[];
      agent.stream.listen((s) {
        final status = s.toolCalls.firstOrNull?.status;
        if (status != null && statuses.lastOrNull != status) {
          statuses.add(status);
        }
      });

      await client.runAgent(agent);
      await pumpEventQueue();

      expect(receivedArgs, {'city': 'Lima'});
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

    test('stays running while the handler runs', () async {
      final handlerDone = Completer<String>();
      await client.registerTool(
        weatherTool((_, {required signal}) => handlerDone.future),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));

      final run = client.runAgent(agent);
      await pumpEventQueue();
      expect(agent.state.isRunning, isTrue);
      expect(agent.state.toolCalls.single.status, ToolCallStatus.executing);

      handlerDone.complete('ok');
      await run;
      expect(agent.state.isRunning, isFalse);
    });

    test('stays running from the first run to the end of the turn', () async {
      await client.registerTool(
        weatherTool((_, {required signal}) async => 'ok'),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));
      final running = <bool>[];
      agent.stream.listen((snapshot) => running.add(snapshot.isRunning));

      await client.runAgent(agent);
      await pumpEventQueue();

      expect(running.last, isFalse);
      expect(running.sublist(0, running.length - 1), everyElement(isTrue));
    });

    test('stays running until a failed turn ends', () async {
      runs.add(
        Stream.fromIterable([
          RunStartedEvent(threadId: agent.state.threadId, runId: 'r1'),
          const RunErrorEvent(message: 'model error'),
        ]),
      );
      final running = <bool>[];
      agent.stream.listen((snapshot) => running.add(snapshot.isRunning));

      await client.runAgent(agent);
      await pumpEventQueue();

      expect(running.last, isFalse);
      expect(running.sublist(0, running.length - 1), everyElement(isTrue));
      expect(errors, hasLength(1));
    });

    test(
      'turns handler errors into a generic result and reports them',
      () async {
        final failure = Exception('no network');
        await client.registerTool(
          weatherTool((_, {required signal}) async => throw failure),
        );
        runs
          ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
          ..add(Stream.fromIterable(replyRun(agent.state.threadId)));

        await client.runAgent(agent);

        expect(errors, [same(failure)]);
        final toolMessage = sentInputs().last.messages.last as ToolMessage;
        expect(toolMessage.content, 'Tool failed.');
        expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
      },
    );

    test('passes the handler the args parsed by the schema', () async {
      Map<String, Object?>? receivedArgs;
      await client.registerTool(
        FrontendTool(
          name: 'showWeather',
          description: 'Show the weather for a city',
          parameters: Ack.object({
            'city': Ack.string(),
            'days': Ack.integer().withDefault(3),
          }),
          handler: (args, {required signal}) async {
            receivedArgs = args;
            return 'ok';
          },
        ),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));

      await client.runAgent(agent);

      expect(receivedArgs, {'city': 'Lima', 'days': 3});
    });

    test('answers invalid args without running the handler', () async {
      var called = false;
      await client.registerTool(
        weatherTool((_, {required signal}) async {
          called = true;
          return '';
        }),
      );
      final events = toolCallRun(agent.state.threadId)
        ..[2] = const ToolCallArgsEvent(
          toolCallId: 'c1',
          delta: '{"days": "3"}',
        );
      runs
        ..add(Stream.fromIterable(events))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));

      await client.runAgent(agent);

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
      runs.add(Stream.fromIterable(toolCallRun(agent.state.threadId)));

      await client.runAgent(agent);

      expect(sentInputs(), hasLength(1));
      final view = agent.state.toolCalls.single;
      expect(view.status, ToolCallStatus.complete);
      expect(view.result, 'Tool is not available.');
      expect(agent.state.messages.last, isA<ToolMessage>());
    });

    test('closes unregistered calls before running again', () async {
      await client.registerTool(
        weatherTool((_, {required signal}) async => 'ok'),
      );
      final events = toolCallRun(agent.state.threadId)
        ..insertAll(4, const [
          ToolCallStartEvent(
            toolCallId: 'c2',
            toolCallName: 'gone',
            parentMessageId: 'a1',
          ),
          ToolCallEndEvent(toolCallId: 'c2'),
        ]);
      runs
        ..add(Stream.fromIterable(events))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));

      await client.runAgent(agent);

      final results = {
        for (final message
            in sentInputs().last.messages.whereType<ToolMessage>())
          message.toolCallId: message.content,
      };
      expect(results, {'c1': 'ok', 'c2': 'Tool is not available.'});
    });

    test('does not run handlers for calls the runtime completed', () async {
      var called = false;
      await client.registerTool(
        weatherTool((_, {required signal}) async {
          called = true;
          return '';
        }),
      );
      final events = toolCallRun(agent.state.threadId)
        ..insert(
          4,
          const ToolCallResultEvent(
            messageId: 't1',
            toolCallId: 'c1',
            content: 'from server',
          ),
        );
      runs.add(Stream.fromIterable(events));

      await client.runAgent(agent);

      expect(called, isFalse);
      expect(sentInputs(), hasLength(1));
      expect(agent.state.toolCalls.single.result, 'from server');
    });

    test('does not run handlers when the run fails', () async {
      var called = false;
      await client.registerTool(
        weatherTool((_, {required signal}) async {
          called = true;
          return '';
        }),
      );
      final events = toolCallRun(agent.state.threadId)
        ..[4] = const RunErrorEvent(message: 'model error');
      runs.add(Stream.fromIterable(events));

      await client.runAgent(agent);

      expect(called, isFalse);
      expect(sentInputs(), hasLength(1));
    });

    test('ignores a run while handlers are running', () async {
      final handlerDone = Completer<String>();
      await client.registerTool(
        weatherTool((_, {required signal}) => handlerDone.future),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.state.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.state.threadId)));
      final run = client.runAgent(agent);
      await pumpEventQueue();

      await client.runAgent(agent);
      handlerDone.complete('ok');
      await run;

      expect(sentInputs(), hasLength(2));
    });

    group('recorded fixtures', () {
      test('runs the handler and sends its result in the next run', () async {
        final calls = <Map<String, Object?>>[];
        await client.registerTool(
          weatherTool((args, {required signal}) async {
            calls.add(args);
            return 'Sunny, 24°C';
          }),
        );
        runs
          ..add(Stream.fromIterable(loadFixture('frontend_tool_call').events))
          ..add(Stream.fromIterable(loadFixture('text_stream').events));

        await client.runAgent(agent);

        expect(calls, [
          {'city': 'Lima'},
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
        runs.add(
          Stream.fromIterable(loadFixture('state_snapshot_delta').events),
        );

        await client.runAgent(agent);

        final call = agent.state.toolCalls.single;
        expect(call.name, 'AGUISendStateDelta');
        expect(call.status, ToolCallStatus.complete);
        expect(call.result, contains('"success":true'));
        expect(sentInputs(), hasLength(1));
        expect(errors, isEmpty);
      });
    });
  });
}
