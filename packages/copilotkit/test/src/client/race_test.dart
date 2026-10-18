import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';
import '../../helpers/tool_loop_harness.dart';

/// A run that calls [names] as calls `c1`, `c2`, … and finishes.
List<BaseEvent> _callsRun(String threadId, List<String> names) => [
  RunStartedEvent(threadId: threadId, runId: 'r1'),
  for (final (i, name) in names.indexed) ...[
    ToolCallStartEvent(
      toolCallId: 'c${i + 1}',
      toolCallName: name,
      parentMessageId: 'a1',
    ),
    ToolCallArgsEvent(toolCallId: 'c${i + 1}', delta: '{"city": "C$i"}'),
    ToolCallEndEvent(toolCallId: 'c${i + 1}'),
  ],
  RunFinishedEvent(threadId: threadId, runId: 'r1'),
];

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('races between stop, run and close', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
    });

    List<String> toolResults() => [
      for (final message in agent.state.messages.whereType<ToolMessage>())
        '${message.toolCallId}=${message.content}',
    ];

    test('a stop while a result is added keeps the next handler from '
        'running', () async {
      final ran = <String>[];
      await client.registerTool(
        weatherTool((args, {required signal}) async {
          ran.add(args['city']! as String);
          return 'done';
        }),
      );
      harness.runs.add(
        Stream.fromIterable(
          _callsRun(agent.threadId, ['showWeather', 'showWeather']),
        ),
      );
      final sub = agent.stream.listen((state) {
        if (state.messages.whereType<ToolMessage>().length == 1) {
          client.add(AgentStopRequested(agent.agentId));
        }
      });

      await client.runAgent(agent);
      await pumpEventQueue();
      await sub.cancel();

      expect(ran, ['C0']);
      expect(toolResults(), ['c1=done', 'c2=Tool call cancelled.']);
      expect(agent.state.isRunning, isFalse);
    });

    test('a run requested right after a stop waits for it and sends '
        'closed tool calls', () async {
      final first = StreamController<BaseEvent>();
      final second = StreamController<BaseEvent>();
      harness.runs.addAll([first.stream, second.stream]);
      unawaited(client.runAgent(agent));
      _callsRun(agent.threadId, ['tool']).take(5).forEach(first.add);
      await pumpEventQueue();

      client
        ..add(AgentStopRequested(agent.agentId))
        ..add(AgentRunRequested(agent.agentId));
      await pumpEventQueue();

      expect(agent.state.isRunning, isTrue);
      final input = harness.sentInputs().last;
      expect(input.messages.last, isA<ToolMessage>());
      expect(toolResults(), ['c1=Tool call cancelled.']);

      second.add(RunFinishedEvent(threadId: agent.threadId, runId: 'r2'));
      await second.close();
      await pumpEventQueue();
      expect(agent.state.isRunning, isFalse);
    });

    test('a second stop while stopping does nothing', () async {
      final events = StreamController<BaseEvent>();
      harness.runs.add(events.stream);
      unawaited(client.runAgent(agent));
      await pumpEventQueue();

      await Future.wait([client.stopAgent(agent), client.stopAgent(agent)]);

      expect(agent.state.isRunning, isFalse);
      expect(client.state.turns, isEmpty);
    });

    test('close while unavailable calls are being closed ends without '
        'uncaught errors', () async {
      harness.runs.add(
        Stream.fromIterable(
          _callsRun(agent.threadId, ['gone', 'gone', 'gone']),
        ),
      );
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final sub = agent.stream.listen((state) {
          if (state.messages.whereType<ToolMessage>().length == 1) {
            unawaited(client.close());
          }
        });
        await client.runAgent(agent);
        await pumpEventQueue();
        await sub.cancel();
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
      expect(harness.errors, isEmpty);
    });

    test('a run waiting for a stop does not start once the client '
        'closes', () async {
      final events = StreamController<BaseEvent>();
      harness.runs.add(events.stream);
      unawaited(client.runAgent(agent));
      await pumpEventQueue();
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        client
          ..add(AgentStopRequested(agent.agentId))
          ..add(AgentRunRequested(agent.agentId));
        await client.close();
        await pumpEventQueue();
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
      verifyRunCount(harness, 1);
    });

    test('a stop while unavailable calls are being closed gives each call '
        'one result', () async {
      harness.runs.add(
        Stream.fromIterable(
          _callsRun(agent.threadId, ['gone', 'gone', 'gone']),
        ),
      );
      final sub = agent.stream.listen((state) {
        if (state.messages.whereType<ToolMessage>().length == 1) {
          client.add(AgentStopRequested(agent.agentId));
        }
      });

      await client.runAgent(agent);
      await pumpEventQueue();
      await sub.cancel();

      expect(toolResults(), [
        'c1=Tool is not available.',
        'c2=Tool call cancelled.',
        'c3=Tool call cancelled.',
      ]);
    });
  });
}

void verifyRunCount(ToolLoopHarness harness, int count) {
  expect(harness.sentInputs(), hasLength(count));
}
