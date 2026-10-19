import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';
import '../../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;
    late List<Stream<BaseEvent>> runs;
    late MockAgentTransport transport;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
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

      blocTest<CopilotKitBloc, CopilotKitState>(
        'when the connection drops after the call ended',
        setUp: () async {
          await client.registerTool(
            weatherTool((_, {required signal}) async => ''),
          );
          runs.add(
            Stream.fromIterable(
              toolCallRun(agent.state.threadId)..removeLast(),
            ),
          );
        },
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          expect(sentInputs(), hasLength(1));
          expectClosedAsFailed();
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'when the runtime reports an error mid-args',
        setUp: () => runs.add(
          Stream.fromIterable([
            ...toolCallRun(agent.state.threadId).take(3),
            const RunErrorEvent(message: 'model error'),
          ]),
        ),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) => expectClosedAsFailed(),
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'so the next run sends a valid conversation',
        setUp: () => runs
          ..add(
            Stream.fromIterable(
              toolCallRun(agent.state.threadId)..removeLast(),
            ),
          )
          ..add(Stream.fromIterable(replyRun(agent.state.threadId))),
        build: () => client,
        act: (_) async {
          await client.runAgent(agent);
          await client.runAgent(agent);
        },
        verify: (_) =>
            expect(sentInputs().last.messages.last, isA<ToolMessage>()),
      );
    });

    group('stop', () {
      late Completer<String> handlerDone;
      late CancellationSignal receivedSignal;

      blocTest<CopilotKitBloc, CopilotKitState>(
        'while the handler runs cancels its signal and does not run again',
        setUp: () async {
          handlerDone = Completer<String>();
          await client.registerTool(
            weatherTool((_, {required signal}) {
              receivedSignal = signal;
              return handlerDone.future;
            }),
          );
          runs.add(Stream.fromIterable(toolCallRun(agent.state.threadId)));
        },
        build: () => client,
        act: (_) async {
          final run = client.runAgent(agent);
          await pumpEventQueue();

          await client.stopAgent(agent);
          handlerDone.complete('late result');
          await run;
        },
        verify: (_) {
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

      blocTest<CopilotKitBloc, CopilotKitState>(
        'while args stream closes the call as cancelled',
        build: () => client,
        act: (_) async {
          final events = StreamController<BaseEvent>();
          runs.add(events.stream);
          final run = client.runAgent(agent);
          events
            ..add(RunStartedEvent(threadId: agent.state.threadId, runId: 'r1'))
            ..add(
              const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'tool'),
            )
            ..add(const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"ci'));
          await pumpEventQueue();

          await client.stopAgent(agent);
          await run;
        },
        verify: (_) {
          expect(agent.state.toolCalls.single.status, ToolCallStatus.complete);
          expect(agent.state.messages.last, isA<ToolMessage>());
        },
      );
    });
  });
}
