import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

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
    late CopilotAgent agent;

    setUp(() {
      transport = _MockAgentTransport();
      errors = [];
      agent = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      ).agent('default');
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
          const ThinkingStartEvent(title: 'plan'),
          const RawEvent(event: {'anything': true}),
          const CustomEvent(name: 'progress', value: 0.5),
          const TextMessageContentEvent(messageId: 'm1', delta: 'lo'),
          RunFinishedEvent(threadId: agent.threadId, runId: 'r'),
        ]);

        await agent.run();

        expect(agent.messages.single.content, 'Hello');
        expect(agent.isRunning, isFalse);
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

      await agent.run();

      expect(errors, [same(runError)]);
      expect(agent.isRunning, isFalse);
      expect(agent.snapshot.error, same(runError));
      expect(agent.messages.single.content, 'Par');
    });
  });
}
