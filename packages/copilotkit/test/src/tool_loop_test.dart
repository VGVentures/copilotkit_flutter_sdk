import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;
    late List<Object> errors;

    setUp(() {
      harness = ToolLoopHarness();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      errors = harness.errors;
    });

    List<RunAgentInput> sentInputs() => harness.sentInputs();

    test('runs the handler, sends the result and runs again', () async {
      Map<String, Object?>? receivedArgs;
      CancellationSignal? receivedSignal;
      client.registerTool(
        weatherTool((args, {required signal}) async {
          receivedArgs = args;
          receivedSignal = signal;
          return '{"forecast": "sunny"}';
        }),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.threadId)));
      final statuses = <ToolCallStatus>[];
      agent.changes.listen((s) {
        final status = s.toolCalls.firstOrNull?.status;
        if (status != null && statuses.lastOrNull != status) {
          statuses.add(status);
        }
      });

      await agent.run();
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
      expect(toolMessage.toolCallId, 'c1');
      expect(toolMessage.content, '{"forecast": "sunny"}');
      expect(agent.toolCalls.single.result, '{"forecast": "sunny"}');
      expect(statuses, [
        ToolCallStatus.inProgress,
        ToolCallStatus.executing,
        ToolCallStatus.complete,
      ]);
      expect(agent.messages.last.content, 'Sunny in Lima');
      expect(agent.isRunning, isFalse);
      expect(errors, isEmpty);
    });

    test('stays running while the handler runs', () async {
      final handlerDone = Completer<String>();
      client.registerTool(
        weatherTool((_, {required signal}) => handlerDone.future),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.threadId)));

      final run = agent.run();
      await pumpEventQueue();
      expect(agent.isRunning, isTrue);
      expect(agent.toolCalls.single.status, ToolCallStatus.executing);

      handlerDone.complete('ok');
      await run;
      expect(agent.isRunning, isFalse);
    });

    test('stays running from the first run to the end of the turn', () async {
      client.registerTool(weatherTool((_, {required signal}) async => 'ok'));
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.threadId)));
      final running = <bool>[];
      agent.changes.listen((snapshot) => running.add(snapshot.isRunning));

      await agent.run();
      await pumpEventQueue();

      expect(running.last, isFalse);
      expect(running.sublist(0, running.length - 1), everyElement(isTrue));
    });

    test('stays running until a failed turn ends', () async {
      runs.add(
        Stream.fromIterable([
          RunStartedEvent(threadId: agent.threadId, runId: 'r1'),
          const RunErrorEvent(message: 'model error'),
        ]),
      );
      final running = <bool>[];
      agent.changes.listen((snapshot) => running.add(snapshot.isRunning));

      await agent.run();
      await pumpEventQueue();

      expect(running.last, isFalse);
      expect(running.sublist(0, running.length - 1), everyElement(isTrue));
      expect(errors, hasLength(1));
    });

    test(
      'turns handler errors into a generic result and reports them',
      () async {
        final failure = Exception('no network');
        client.registerTool(
          weatherTool((_, {required signal}) async => throw failure),
        );
        runs
          ..add(Stream.fromIterable(toolCallRun(agent.threadId)))
          ..add(Stream.fromIterable(replyRun(agent.threadId)));

        await agent.run();

        expect(errors, [same(failure)]);
        final toolMessage = sentInputs().last.messages.last as ToolMessage;
        expect(toolMessage.content, 'Tool failed.');
        expect(agent.toolCalls.single.status, ToolCallStatus.complete);
      },
    );

    test('closes calls to unregistered tools as unavailable', () async {
      runs.add(Stream.fromIterable(toolCallRun(agent.threadId)));

      await agent.run();

      expect(sentInputs(), hasLength(1));
      final view = agent.toolCalls.single;
      expect(view.status, ToolCallStatus.complete);
      expect(view.result, 'Tool is not available.');
      expect(agent.messages.last, isA<ToolMessage>());
    });

    test('closes unregistered calls before running again', () async {
      client.registerTool(weatherTool((_, {required signal}) async => 'ok'));
      final events = toolCallRun(agent.threadId)
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
        ..add(Stream.fromIterable(replyRun(agent.threadId)));

      await agent.run();

      final results = {
        for (final message
            in sentInputs().last.messages.whereType<ToolMessage>())
          message.toolCallId: message.content,
      };
      expect(results, {'c1': 'ok', 'c2': 'Tool is not available.'});
    });

    test('does not run handlers for calls the runtime completed', () async {
      var called = false;
      client.registerTool(
        weatherTool((_, {required signal}) async {
          called = true;
          return '';
        }),
      );
      final events = toolCallRun(agent.threadId)
        ..insert(
          4,
          const ToolCallResultEvent(
            messageId: 't1',
            toolCallId: 'c1',
            content: 'from server',
          ),
        );
      runs.add(Stream.fromIterable(events));

      await agent.run();

      expect(called, isFalse);
      expect(sentInputs(), hasLength(1));
      expect(agent.toolCalls.single.result, 'from server');
    });

    test('does not run handlers when the run fails', () async {
      var called = false;
      client.registerTool(
        weatherTool((_, {required signal}) async {
          called = true;
          return '';
        }),
      );
      final events = toolCallRun(agent.threadId)
        ..[4] = const RunErrorEvent(message: 'model error');
      runs.add(Stream.fromIterable(events));

      await agent.run();

      expect(called, isFalse);
      expect(sentInputs(), hasLength(1));
    });

    test('ignores a run while handlers are running', () async {
      final handlerDone = Completer<String>();
      client.registerTool(
        weatherTool((_, {required signal}) => handlerDone.future),
      );
      runs
        ..add(Stream.fromIterable(toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(replyRun(agent.threadId)));
      final run = agent.run();
      await pumpEventQueue();

      await agent.run();
      handlerDone.complete('ok');
      await run;

      expect(sentInputs(), hasLength(2));
    });
  });
}
