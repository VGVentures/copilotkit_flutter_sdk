import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

List<BaseEvent> _toolCallRun(String threadId, {String name = 'showWeather'}) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r1'),
    ToolCallStartEvent(
      toolCallId: 'c1',
      toolCallName: name,
      parentMessageId: 'a1',
    ),
    const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": "Lima"}'),
    const ToolCallEndEvent(toolCallId: 'c1'),
    RunFinishedEvent(threadId: threadId, runId: 'r1'),
  ];
}

List<BaseEvent> _replyRun(String threadId) {
  return [
    RunStartedEvent(threadId: threadId, runId: 'r2'),
    const TextMessageStartEvent(messageId: 'a2'),
    const TextMessageContentEvent(messageId: 'a2', delta: 'Sunny in Lima'),
    RunFinishedEvent(threadId: threadId, runId: 'r2'),
  ];
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  });

  group('frontend tools', () {
    late _MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;

    setUp(() {
      transport = _MockAgentTransport();
      errors = [];
      runs = [];
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => runs.removeAt(0));
      when(
        () => transport.stop(
          agentId: any(named: 'agentId'),
          threadId: any(named: 'threadId'),
          runId: any(named: 'runId'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {});
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
      agent = client.agent('default');
    });

    List<RunAgentInput> sentInputs() {
      return verify(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: captureAny(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).captured.cast<RunAgentInput>();
    }

    FrontendTool weatherTool(FrontendToolHandler handler) {
      return FrontendTool(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: Ack.object({
          'city': Ack.string().describe('City name'),
          'days': Ack.integer().optional(),
        }),
        handler: handler,
      );
    }

    group('registerTool', () {
      test('sends registered tools with their JSON Schema', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''));
        runs.add(const Stream.empty());

        await agent.run();

        final tool = sentInputs().single.tools.single;
        expect(tool.name, 'showWeather');
        expect(tool.description, 'Show the weather for a city');
        expect(tool.parameters, {
          'type': 'object',
          'properties': {
            'city': {'type': 'string', 'description': 'City name'},
            'days': {'type': 'integer'},
          },
          'required': ['city'],
          'additionalProperties': false,
        });
      });

      test('sends empty properties for empty object schemas', () async {
        client.registerTool(
          FrontendTool(
            name: 'refresh',
            description: 'Refresh the screen',
            parameters: Ack.object({'options': Ack.object({})}),
            handler: (_, {required signal}) async => '',
          ),
        );
        runs.add(const Stream.empty());

        await agent.run();

        expect(sentInputs().single.tools.single.parameters, {
          'type': 'object',
          'properties': {
            'options': {
              'type': 'object',
              'additionalProperties': false,
              'properties': <String, Object?>{},
            },
          },
          'required': ['options'],
          'additionalProperties': false,
        });
      });

      test('the returned function unregisters the tool', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''))();
        runs.add(const Stream.empty());

        await agent.run();

        expect(sentInputs().single.tools, isEmpty);
      });

      test(
        'a stale unregister keeps a newer tool with the same name',
        () async {
          final unregisterOld = client.registerTool(
            weatherTool((_, {required signal}) async => 'old'),
          );
          client.registerTool(
            weatherTool((_, {required signal}) async => 'new'),
          );
          unregisterOld();
          runs.add(const Stream.empty());

          await agent.run();

          expect(sentInputs().single.tools, hasLength(1));
        },
      );
    });

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
        ..add(Stream.fromIterable(_toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(_replyRun(agent.threadId)));
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
        ..add(Stream.fromIterable(_toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(_replyRun(agent.threadId)));

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
        ..add(Stream.fromIterable(_toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(_replyRun(agent.threadId)));
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
          ..add(Stream.fromIterable(_toolCallRun(agent.threadId)))
          ..add(Stream.fromIterable(_replyRun(agent.threadId)));

        await agent.run();

        expect(errors, [same(failure)]);
        final toolMessage = sentInputs().last.messages.last as ToolMessage;
        expect(toolMessage.content, 'Tool failed.');
        expect(agent.toolCalls.single.status, ToolCallStatus.complete);
      },
    );

    test('closes calls to unregistered tools as unavailable', () async {
      runs.add(Stream.fromIterable(_toolCallRun(agent.threadId)));

      await agent.run();

      expect(sentInputs(), hasLength(1));
      final view = agent.toolCalls.single;
      expect(view.status, ToolCallStatus.complete);
      expect(view.result, 'Tool is not available.');
      expect(agent.messages.last, isA<ToolMessage>());
    });

    test('closes unregistered calls before running again', () async {
      client.registerTool(weatherTool((_, {required signal}) async => 'ok'));
      final events = _toolCallRun(agent.threadId)
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
        ..add(Stream.fromIterable(_replyRun(agent.threadId)));

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
      final events = _toolCallRun(agent.threadId)
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
      final events = _toolCallRun(agent.threadId)
        ..[4] = const RunErrorEvent(message: 'model error');
      runs.add(Stream.fromIterable(events));

      await agent.run();

      expect(called, isFalse);
      expect(sentInputs(), hasLength(1));
    });

    group('a failed run closes open calls', () {
      void expectClosedAsFailed() {
        final view = agent.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, 'Tool call failed: the run ended early.');
        final message = agent.messages.whereType<ToolMessage>().single;
        expect(message.toolCallId, 'c1');
        expect(message.content, view.result);
      }

      test('when the connection drops after the call ended', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''));
        runs.add(
          Stream.fromIterable(_toolCallRun(agent.threadId)..removeLast()),
        );

        await agent.run();

        expect(sentInputs(), hasLength(1));
        expectClosedAsFailed();
      });

      test('when the runtime reports an error mid-args', () async {
        runs.add(
          Stream.fromIterable([
            ..._toolCallRun(agent.threadId).take(3),
            const RunErrorEvent(message: 'model error'),
          ]),
        );

        await agent.run();

        expectClosedAsFailed();
      });

      test('so the next run sends a valid conversation', () async {
        runs
          ..add(Stream.fromIterable(_toolCallRun(agent.threadId)..removeLast()))
          ..add(Stream.fromIterable(_replyRun(agent.threadId)));
        await agent.run();

        await agent.run();

        final messages = sentInputs().last.messages;
        expect(messages.last, isA<ToolMessage>());
      });
    });

    group('stop', () {
      test('while the handler runs cancels its signal and does not run '
          'again', () async {
        final handlerDone = Completer<String>();
        late CancellationSignal receivedSignal;
        client.registerTool(
          weatherTool((_, {required signal}) {
            receivedSignal = signal;
            return handlerDone.future;
          }),
        );
        runs.add(Stream.fromIterable(_toolCallRun(agent.threadId)));
        final run = agent.run();
        await pumpEventQueue();

        await agent.stop();
        handlerDone.complete('late result');
        await run;

        expect(receivedSignal.isCancelled, isTrue);
        expect(sentInputs(), hasLength(1));
        expect(agent.isRunning, isFalse);
        final view = agent.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, 'Tool call cancelled.');
        expect(
          agent.messages.whereType<ToolMessage>().single.content,
          'Tool call cancelled.',
        );
        verifyNever(
          () => transport.stop(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
            runId: any(named: 'runId'),
            headers: any(named: 'headers'),
          ),
        );
      });

      test('while args stream closes the call as cancelled', () async {
        final events = StreamController<BaseEvent>();
        runs.add(events.stream);
        final run = agent.run();
        events
          ..add(RunStartedEvent(threadId: agent.threadId, runId: 'r1'))
          ..add(
            const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
          )
          ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'));
        await pumpEventQueue();

        await agent.stop();
        await run;

        expect(agent.toolCalls.single.status, ToolCallStatus.complete);
        expect(agent.messages.last, isA<ToolMessage>());
      });
    });

    test('ignores a run while handlers are running', () async {
      final handlerDone = Completer<String>();
      client.registerTool(
        weatherTool((_, {required signal}) => handlerDone.future),
      );
      runs
        ..add(Stream.fromIterable(_toolCallRun(agent.threadId)))
        ..add(Stream.fromIterable(_replyRun(agent.threadId)));
      final run = agent.run();
      await pumpEventQueue();

      await agent.run();
      handlerDone.complete('ok');
      await run;

      expect(sentInputs(), hasLength(2));
    });
  });
}
