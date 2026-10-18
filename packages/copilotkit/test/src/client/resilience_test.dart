import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';
import '../../helpers/fixtures.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

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

  group('resilience', () {
    late _MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;
    late CopilotAgent agent;

    setUp(() async {
      transport = _MockAgentTransport();
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
      agent = await client.openAgent('default');
    });

    void stubRun(List<BaseEvent> events) {
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => Stream.fromIterable(events));
    }

    test(
      'reasoning, activity, raw and custom events leave text intact',
      () async {
        stubRun([
          RunStartedEvent(threadId: agent.threadId, runId: 'r'),
          const ReasoningStartEvent(messageId: 'think'),
          const ReasoningMessageContentEvent(messageId: 'think', delta: 'Hmm'),
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Hel'),
          const ActivitySnapshotEvent(
            messageId: 'act',
            activityType: 'search',
            content: {'query': 'weather'},
          ),
          const StepStartedEvent(stepName: 'plan'),
          const RawEvent(event: {'anything': true}),
          const CustomEvent(name: 'progress', value: 0.5),
          const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
          RunFinishedEvent(threadId: agent.threadId, runId: 'r'),
        ]);

        await client.runAgent(agent);

        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      },
    );

    test('RUN_ERROR ends the run and reports the error once', () async {
      const runError = RunErrorEvent(message: 'Invalid API key', code: 'AUTH');
      stubRun([
        RunStartedEvent(threadId: agent.threadId, runId: 'r'),
        const TextMessageStartEvent(messageId: 'm1'),
        const TextMessageContentEvent(messageId: 'm1', delta: 'Par'),
        runError,
      ]);

      await client.runAgent(agent);

      expect(errors, [same(runError)]);
      expect(agent.state.isRunning, isFalse);
      expect(agent.state.error, same(runError));
      expect(agent.state.messages.single.content, 'Par');
    });

    test('unknown_events fixture keeps the text reply', () async {
      stubRun(loadFixture('unknown_events').events);

      await client.runAgent(agent);

      expect(
        agent.state.messages.single.content,
        'Hello! Wonderful to meet you.',
      );
      expect(agent.state.isRunning, isFalse);
      expect(errors, isEmpty);
    });

    test('recorded run_error fixture reports the runtime error', () async {
      stubRun(loadFixture('run_error').events);

      await client.runAgent(agent);

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

    test('dropped_connection fixture fails the run and keeps the partial '
        'reply', () async {
      stubRun(loadFixture('dropped_connection').events);

      await client.runAgent(agent);

      expect(errors.single, isA<StateError>());
      expect(agent.state.messages.single.content, 'Hello! Wonderful to');
      expect(agent.state.isRunning, isFalse);
    });
  });
}
