import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient frontend tools', () {
    late ClientHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;
    late MockAgentTransport transport;

    setUp(() async {
      harness = ClientHarness();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      transport = harness.transport;
    });

    List<RunAgentInput> sentInputs() => harness.transport.sentInputs();

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
        client.registerTool(weatherTool((_, {required signal}) async => ''));
        runs.add(
          Stream.fromIterable(toolCallRun(agent.state.threadId)..removeLast()),
        );

        await client.runAgent(agent.state.agentId);
        expect(sentInputs(), hasLength(1));
        expectClosedAsFailed();
      });

      test('when the runtime reports an error mid-args', () async {
        runs.add(
          Stream.fromIterable([
            ...toolCallRun(agent.state.threadId).take(3),
            const RunErrorEvent(message: 'model error'),
          ]),
        );
        await client.runAgent(agent.state.agentId);
        expectClosedAsFailed();
      });

      test('so the next run sends a valid conversation', () async {
        runs
          ..add(
            Stream.fromIterable(
              toolCallRun(agent.state.threadId)..removeLast(),
            ),
          )
          ..add(Stream.fromIterable(replyRun(agent.state.threadId)));
        await client.runAgent(agent.state.agentId);
        await client.runAgent(agent.state.agentId);

        expect(sentInputs().last.messages.last, isA<ToolMessage>());
      });
    });

    group('stop', () {
      late Completer<String> handlerDone;
      late CancellationSignal receivedSignal;

      test(
        'while the handler runs cancels its signal and does not run again',
        () async {
          handlerDone = Completer<String>();
          client.registerTool(
            weatherTool((_, {required signal}) {
              receivedSignal = signal;
              return handlerDone.future;
            }),
          );
          runs.add(Stream.fromIterable(toolCallRun(agent.state.threadId)));

          final run = client.runAgent(agent.state.agentId);
          await pumpEventQueue();

          await client.stopAgent(agent.state.agentId);
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
          transport.verifyNoStop();
        },
      );

      test('while args stream closes the call as cancelled', () async {
        final events = StreamController<BaseEvent>();
        runs.add(events.stream);
        final run = client.runAgent(agent.state.agentId);
        events
          ..add(RunStartedEvent(threadId: agent.state.threadId, runId: 'r1'))
          ..add(
            const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
          )
          ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'));
        await pumpEventQueue();

        await client.stopAgent(agent.state.agentId);
        await run;

        expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
        expect(agent.state.messages.last, isA<ToolMessage>());
      });
    });
  });
}
