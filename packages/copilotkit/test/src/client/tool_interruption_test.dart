import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';
import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;
    late AgentTransport transport;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      transport = harness.transport;
    });

    List<RunAgentInput> sentInputs() => harness.sentInputs();

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
        await client.registerTool(
          weatherTool((_, {required signal}) async => ''),
        );
        runs.add(
          Stream.fromIterable(toolCallRun(agent.threadId)..removeLast()),
        );

        await client.runAgent(agent);

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

        await client.runAgent(agent);

        expectClosedAsFailed();
      });

      test('so the next run sends a valid conversation', () async {
        runs
          ..add(Stream.fromIterable(toolCallRun(agent.threadId)..removeLast()))
          ..add(Stream.fromIterable(replyRun(agent.threadId)));
        await client.runAgent(agent);

        await client.runAgent(agent);

        final messages = sentInputs().last.messages;
        expect(messages.last, isA<ToolMessage>());
      });
    });

    group('stop', () {
      test('while the handler runs cancels its signal and does not run '
          'again', () async {
        final handlerDone = Completer<String>();
        late CancellationSignal receivedSignal;
        await client.registerTool(
          weatherTool((_, {required signal}) {
            receivedSignal = signal;
            return handlerDone.future;
          }),
        );
        runs.add(Stream.fromIterable(toolCallRun(agent.threadId)));
        final run = client.runAgent(agent);
        await pumpEventQueue();

        await client.stopAgent(agent);
        handlerDone.complete('late result');
        await run;

        expect(receivedSignal.isCancelled, isTrue);
        expect(sentInputs(), hasLength(1));
        expect(agent.state.isRunning, isFalse);
        final view = agent.state.toolCalls.single;
        expect(view.status, ToolCallStatus.complete);
        expect(view.result, 'Tool call cancelled.');
        expect(
          agent.state.messages.whereType<ToolMessage>().single.content,
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
        final run = client.runAgent(agent);
        events
          ..add(RunStartedEvent(threadId: agent.threadId, runId: 'r1'))
          ..add(
            const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
          )
          ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'));
        await pumpEventQueue();

        await client.stopAgent(agent);
        await run;

        expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
        expect(agent.state.messages.last, isA<ToolMessage>());
      });
    });
  });
}
