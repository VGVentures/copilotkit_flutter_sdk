import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mock_agent_transport.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient resilience', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;
    late CopilotAgent agent;

    setUp(() async {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
      agent = client.agent('default');
    });

    void stubRun(List<BaseEvent> Function(String threadId) events) {
      transport.stubRun(
        () => Stream.fromIterable(events(agent.state.threadId)),
      );
    }

    test(
      'reasoning, activity, raw and custom events leave text intact',
      () async {
        stubRun(
          (threadId) => [
            RunStartedEvent(threadId: threadId, runId: 'r'),
            const ReasoningStartEvent(messageId: 'think'),
            const ReasoningMessageContentEvent(
              messageId: 'think',
              delta: 'Hmm',
            ),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
            const ActivitySnapshotEvent(
              messageId: 'act',
              activityType: 'search',
              content: {'query': 'weather'},
            ),
            const ThinkingStartEvent(title: 'plan'),
            const RawEvent(event: {'anything': true}),
            const CustomEvent(name: 'progress', value: 0.5),
            const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
            RunFinishedEvent(threadId: threadId, runId: 'r'),
          ],
        );
        await client.runAgent(agent.state.agentId);
        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      },
    );

    const runError = RunErrorEvent(message: 'Invalid API key', code: 'AUTH');

    test('RUN_ERROR ends the run and reports the error once', () async {
      stubRun(
        (threadId) => [
          RunStartedEvent(threadId: threadId, runId: 'r'),
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Par'),
          runError,
        ],
      );
      await client.runAgent(agent.state.agentId);
      expect(errors, [same(runError)]);
      expect(agent.state.isRunning, isFalse);
      expect(agent.state.error, same(runError));
      expect(agent.state.messages.single.content, 'Par');
    });

    test('unknown_events fixture keeps the text reply', () async {
      stubRun((_) => loadFixture('unknown_events').events);
      await client.runAgent(agent.state.agentId);
      expect(
        agent.state.messages.single.content,
        'Hello! Wonderful to meet you.',
      );
      expect(agent.state.isRunning, isFalse);
      expect(errors, isEmpty);
    });

    test('recorded run_error fixture reports the runtime error', () async {
      stubRun((_) => loadFixture('run_error').events);
      await client.runAgent(agent.state.agentId);
      expect(errors.single, isA<RunErrorEvent>());
      expect(
        agent.state.error,
        isA<RunErrorEvent>().having(
          (error) => error.message,
          'message',
          contains('gemini-2.5-flash'),
        ),
      );
      expect(agent.state.isRunning, isFalse);
    });

    test(
      'dropped_connection fixture fails the run and keeps the partial reply',
      () async {
        stubRun((_) => loadFixture('dropped_connection').events);
        await client.runAgent(agent.state.agentId);
        expect(errors.single, isA<StateError>());
        expect(agent.state.messages.single.content, 'Hello! Wonderful to');
        expect(agent.state.isRunning, isFalse);
      },
    );
  });
}
