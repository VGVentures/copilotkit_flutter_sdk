import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/json_values.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group(CopilotKitClient, () {
    final runtimeUrl = Uri.parse('http://runtime.test/api/copilotkit');
    late MockAgentTransport transport;
    late List<(Object, StackTrace)> errors;
    late CopilotKitClient client;

    setUp(() {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: runtimeUrl,
        headers: () async => {'Authorization': 'Bearer token'},
        properties: const {'userId': '42'},
        onError: (error, stackTrace) => errors.add((error, stackTrace)),
        transport: transport,
      );
    });

    void stubRun(Stream<BaseEvent> events) {
      transport.stubRun(() => events);
    }

    /// The input of the only run sent so far.
    RunAgentInput sentInput() => transport.sentInputs().single;

    test('starts with no agents, tools or context', () {
      expect(client.agents, isEmpty);
      expect(client.tools, isEmpty);
      expect(client.context, isEmpty);
    });

    test('creates a default transport when none is given', () async {
      final client = CopilotKitClient(runtimeUrl: runtimeUrl);

      await expectLater(client.close(), completes);
    });

    group('tools and context', () {
      final tool = FrontendTool(
        name: 'showWeather',
        description: 'Weather',
        parameters: Ack.object({}),
        decode: JsonObject.new,
        handler: (_, {required signal}) async => '',
      );
      final entry = AgentContextEntry(
        id: 'e1',
        description: 'Unread',
        value: const Count(3),
      );

      test('registerTool and unregisterTool add and remove the tool', () {
        client.registerTool(tool);
        expect(client.tools, {'showWeather': tool});

        client.unregisterTool(tool);
        expect(client.tools, isEmpty);
      });

      test('addContext, updateContext and removeContext edit the context', () {
        client.addContext(entry);
        expect(client.context, [entry]);

        client.updateContext('e1', const Count(4));
        expect(client.context, [entry.copyWith(value: const Count(4))]);

        client.removeContext('e1');
        expect(client.context, isEmpty);
      });

      test('exposes read-only views', () {
        expect(() => client.tools['x'] = tool, throwsUnsupportedError);
        expect(() => client.context.add(entry), throwsUnsupportedError);
        expect(
          () => client.agents['x'] = CopilotAgent(agentId: 'x'),
          throwsUnsupportedError,
        );
      });
    });

    group('agent', () {
      test('opens an idle, empty agent once', () {
        final agent = client.agent('default');

        expect(client.agent('default'), same(agent));
        expect(client.agents.keys, ['default']);
        expect(agent.state.agentId, 'default');
        expect(agent.state.messages, isEmpty);
        expect(agent.state.sharedState, isNull);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.toolCalls, isEmpty);
        expect(agent.state.error, isNull);
      });

      test('gives each agent its own thread', () {
        final a = client.agent('a').state.threadId;
        final b = client.agent('b').state.threadId;

        expect(Uuid.isValidUUID(fromString: a), isTrue);
        expect(a, isNot(b));
      });
    });

    group('runAgent', () {
      final message = UserMessage(id: 'u1', content: 'Hi');

      test('runs the agent with its tools, context and properties', () async {
        final agent = client.agent('default');
        client
          ..registerTool(
            FrontendTool(
              name: 'showWeather',
              description: 'Weather',
              parameters: Ack.object({}),
              decode: JsonObject.new,
              handler: (_, {required signal}) async => '',
            ),
          )
          ..addContext(
            AgentContextEntry(description: 'Unread', value: const Count(3)),
          );
        stubRun(
          Stream.fromIterable([
            RunStartedEvent(threadId: agent.state.threadId, runId: 'r'),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'Hello'),
            RunFinishedEvent(threadId: agent.state.threadId, runId: 'r'),
          ]),
        );

        await client.runAgent('default', message: message);

        final input =
            verify(
                  () => transport.run(
                    agentId: 'default',
                    input: captureAny(named: 'input'),
                    headers: {'Authorization': 'Bearer token'},
                  ),
                ).captured.single
                as RunAgentInput;
        expect(input.messages, [message]);
        expect(input.tools.single.name, 'showWeather');
        expect(input.context.single.value, '3');
        expect(input.forwardedProps, {'userId': '42'});
        expect(agent.state.messages.last.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
      });

      test('opens an agent that was never opened', () async {
        stubRun(const Stream.empty());

        await client.runAgent('other');

        expect(client.agents.keys, ['other']);
        expect(sentInput().threadId, client.agents['other']!.state.threadId);
      });

      final failure = Exception('connection refused');

      test('reports errors to onError', () async {
        final agent = client.agent('default');
        stubRun(Stream.error(failure));

        await client.runAgent('default');

        expect(errors.single.$1, same(failure));
        expect(agent.state.error, same(failure));
      });

      test(
        'logs errors instead of throwing without an onError handler',
        () async {
          client = CopilotKitClient(
            runtimeUrl: runtimeUrl,
            transport: transport,
          );
          final agent = client.agent('default');
          stubRun(Stream.error(Exception('boom')));

          await client.runAgent('default');

          expect(agent.state.error, isA<Exception>());
        },
      );
    });

    group('stopAgent', () {
      test('stops the turn of a running agent', () async {
        final agent = client.agent('default');
        final events = StreamController<BaseEvent>();
        stubRun(events.stream);
        transport.stubStop();
        final run = client.runAgent('default');
        events.add(RunStartedEvent(threadId: agent.state.threadId, runId: 'r'));
        await pumpEventQueue();

        await client.stopAgent('default');
        await run;

        expect(agent.state.isRunning, isFalse);
        verify(
          () => transport.stop(
            agentId: 'default',
            threadId: agent.state.threadId,
            runId: any(named: 'runId'),
            headers: any(named: 'headers'),
          ),
        ).called(1);
      });

      test('does nothing for an agent that was never opened', () async {
        await client.stopAgent('missing');

        expect(client.agents, isEmpty);
        transport.verifyNoStop();
      });
    });

    group('close', () {
      test('closes the transport and the agents', () async {
        final agent = client.agent('default');
        final changesDone = agent.stream.drain<void>();

        await client.close();

        verify(() => transport.close()).called(1);
        await expectLater(changesDone, completes);
        expect(agent.isClosed, isTrue);
      });

      test('cancels active runs', () async {
        var cancelled = false;
        stubRun(
          StreamController<BaseEvent>(onCancel: () => cancelled = true).stream,
        );
        final run = client.runAgent('default');
        await pumpEventQueue();

        await client.close();
        await run;

        expect(cancelled, isTrue);
      });
    });

    group('human-in-the-loop tools', () {
      late ClientHarness harness;
      late CopilotKitClient client;
      late CopilotAgent agent;
      late HumanInTheLoopTool<JsonObject> tool;
      late Future<void> run;

      setUp(() async {
        harness = ClientHarness();
        client = harness.client;
        agent = harness.agent;
        tool = approvalTool();
        client.registerTool(tool);
        harness.runs
          ..add(Stream.fromIterable(approvalRun(agent.state.threadId)))
          ..add(Stream.fromIterable(replyRun(agent.state.threadId)));
        run = client.runAgent(agent.state.agentId);
        await pumpEventQueue();
      });

      /// The tool messages sent with the last run, by call.
      Map<String, String> sentResults() => {
        for (final message
            in harness.transport
                .sentInputs()
                .last
                .messages
                .whereType<ToolMessage>())
          message.toolCallId: message.content,
      };

      test('respondToToolCall answers the waiting call', () async {
        expect(agent.state.awaitingResponseIds, ['c1']);

        client.respondToToolCall('c1', 'approved');
        await run;

        expect(sentResults(), {'c1': 'approved'});
      });

      test('unregisterTool answers the waiting calls as cancelled', () async {
        client.unregisterTool(tool);
        await run;

        expect(client.tools, isEmpty);
        expect(sentResults(), {'c1': 'Tool call cancelled.'});
      });

      test('keeps the call waiting when the tool was replaced first', () async {
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

      test('unregistering a frontend tool cancels nothing', () async {
        final weather = weatherTool((_, {required signal}) async => '');
        client
          ..registerTool(weather)
          ..unregisterTool(weather);
        await pumpEventQueue();
        final mid = agent.state.awaitingResponseIds;
        client.respondToToolCall('c1', 'ok');
        await run;

        expect(mid, ['c1']);
        expect(sentResults(), {'c1': 'ok'});
      });
    });
  });
}
