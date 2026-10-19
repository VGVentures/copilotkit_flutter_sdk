import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';
import '../../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('component tools', () {
    late ToolLoopHarness harness;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;
    late List<Stream<BaseEvent>> runs;
    // The inputs of every run, read once: the mock counts a verified call
    // only once.
    List<RunAgentInput>? inputs;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
      inputs = null;
      await client.registerTool(cardTool());
    });

    List<RunAgentInput> sentInputs() =>
        inputs ??= harness.transport.sentInputs();

    String threadId() => agent.state.threadId;

    Stream<BaseEvent> cardRun() =>
        Stream.fromIterable(toolCallRun(threadId(), name: 'showCard'));

    blocTest<CopilotKitBloc, CopilotKitState>(
      'renders the call and ends the turn without running the agent again',
      setUp: () => runs
        ..add(cardRun())
        ..add(Stream.fromIterable(replyRun(threadId()))),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(sentInputs(), hasLength(1));
        final call = agent.state.toolCalls.single;
        expect(call.status, ToolCallStatus.complete);
        expect(call.args, {'city': 'Lima'});
        expect(call.awaitingResponse, isFalse);
        expect(agent.state.isRunning, isFalse);
        expect(harness.errors, isEmpty);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'closes the call with a note so the next run sends a valid conversation',
      setUp: () => runs
        ..add(cardRun())
        ..add(Stream.fromIterable(replyRun(threadId()))),
      build: () => client,
      act: (_) async {
        await client.runAgent(agent);
        await client.runAgent(
          agent,
          message: UserMessage(id: 'u1', content: 'Thanks'),
        );
      },
      verify: (_) {
        final messages = sentInputs().last.messages;
        final assistant = messages.whereType<AssistantMessage>().single;
        final result = messages.whereType<ToolMessage>().single;
        expect(assistant.toolCalls!.single.id, 'c1');
        expect(result.toolCallId, 'c1');
        expect(result.content, 'The component was displayed to the user.');
        expect(messages.indexOf(result), messages.indexOf(assistant) + 1);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'adds nothing when the runtime already answered the call',
      setUp: () => runs.add(
        Stream.fromIterable([
          ...toolCallRun(threadId(), name: 'showCard').take(4),
          const ToolCallResultEvent(
            messageId: 'm1',
            toolCallId: 'c1',
            content: 'Forwarded to client',
          ),
          RunFinishedEvent(threadId: threadId(), runId: 'r1'),
        ]),
      ),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(sentInputs(), hasLength(1));
        final message = agent.state.messages.whereType<ToolMessage>().single;
        expect(message.content, 'Forwarded to client');
        expect(agent.state.toolCalls.single.result, 'Forwarded to client');
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'runs the agent again when another call in the turn follows up',
      setUp: () async {
        await client.registerTool(
          weatherTool((_, {required signal}) async => 'sunny'),
        );
        runs
          ..add(
            Stream.fromIterable([
              RunStartedEvent(threadId: threadId(), runId: 'r1'),
              ...toolCallRun(threadId(), name: 'showCard').sublist(1, 4),
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
      },
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(sentInputs(), hasLength(2));
        final results = {
          for (final message
              in sentInputs().last.messages.whereType<ToolMessage>())
            message.toolCallId: message.content,
        };
        expect(results, {
          'c1': 'The component was displayed to the user.',
          'c2': 'sunny',
        });
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'tells the agent when its arguments do not match, and runs again',
      setUp: () => runs
        ..add(
          Stream.fromIterable([
            ...toolCallRun(threadId(), name: 'showCard').take(2),
            const ToolCallArgsEvent(toolCallId: 'c1', delta: '{"city": 1}'),
            const ToolCallEndEvent(toolCallId: 'c1'),
            RunFinishedEvent(threadId: threadId(), runId: 'r1'),
          ]),
        )
        ..add(Stream.fromIterable(replyRun(threadId()))),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(sentInputs(), hasLength(2));
        final result = sentInputs().last.messages
            .whereType<ToolMessage>()
            .single;
        expect(result.content, contains("arguments don't match"));
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'is sent to the agent with the sentence that it renders a component',
      setUp: () => runs.add(const Stream.empty()),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        final tool = sentInputs().single.tools.single;
        expect(tool.name, 'showCard');
        expect(
          tool.description,
          startsWith('Use this tool to display the "showCard" component'),
        );
        expect((tool.parameters as Map<String, Object?>)['required'], ['city']);
      },
    );

    group('agent id', () {
      late CopilotAgentBloc other;

      setUp(() async {
        other = await client.openAgent('other');
        await client.registerTool(cardTool(agentId: 'other'));
      });

      blocTest<CopilotKitBloc, CopilotKitState>(
        'sends the tool only to its agent',
        setUp: () => runs
          ..add(const Stream.empty())
          ..add(const Stream.empty()),
        build: () => client,
        act: (_) async {
          await client.runAgent(agent);
          await client.runAgent(other);
        },
        verify: (_) {
          final [first, second] = sentInputs();
          expect(first.tools, isEmpty);
          expect(second.tools.map((tool) => tool.name), ['showCard']);
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'answers a call to it from another agent as unavailable',
        setUp: () => runs.add(cardRun()),
        build: () => client,
        act: (_) => client.runAgent(agent),
        verify: (_) {
          final call = agent.state.toolCalls.single;
          expect(call.result, 'Tool is not available.');
          expect(sentInputs(), hasLength(1));
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'handles a call from its agent',
        setUp: () => runs.add(
          Stream.fromIterable(
            toolCallRun(other.state.threadId, name: 'showCard'),
          ),
        ),
        build: () => client,
        act: (_) => client.runAgent(other),
        verify: (_) => expect(
          other.state.toolCalls.single.result,
          'The component was displayed to the user.',
        ),
      );
    });

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a human-in-the-loop tool that does not follow up still runs again for '
      'arguments that do not match',
      setUp: () async {
        await client.registerTool(approvalTool(followUp: false));
        runs
          ..add(
            Stream.fromIterable(approvalRun(threadId(), args: '{"action": 1}')),
          )
          ..add(Stream.fromIterable(replyRun(threadId())));
      },
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) => expect(sentInputs(), hasLength(2)),
    );
  });
}
