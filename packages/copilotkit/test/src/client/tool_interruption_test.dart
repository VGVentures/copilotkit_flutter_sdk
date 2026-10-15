import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;
    late AgentTransport transport;

    setUp(() {
      harness = ToolLoopHarness();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      transport = harness.transport;
    });

    List<RunAgentInput> sentInputs() => harness.sentInputs();

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
          Stream.fromIterable(toolCallRun(agent.threadId)..removeLast()),
        );

        await agent.run();

        expect(sentInputs(), hasLength(1));
        expectClosedAsFailed();
      });

      test('when the runtime reports an error mid-args', () async {
        runs.add(
          Stream.fromIterable([
            ...toolCallRun(agent.threadId).take(3),
            const RunErrorEvent(message: 'model error'),
          ]),
        );

        await agent.run();

        expectClosedAsFailed();
      });

      test('so the next run sends a valid conversation', () async {
        runs
          ..add(Stream.fromIterable(toolCallRun(agent.threadId)..removeLast()))
          ..add(Stream.fromIterable(replyRun(agent.threadId)));
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
        runs.add(Stream.fromIterable(toolCallRun(agent.threadId)));
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
  });
}
