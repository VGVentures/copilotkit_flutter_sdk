import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('resilience', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;

    setUp(() async {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      client = TestCopilotKitBloc(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
      agent = await client.openAgent('default');
    });

    void stubRun(List<BaseEvent> Function(String threadId) events) {
      transport.stubRun(
        () => Stream.fromIterable(events(agent.state.threadId)),
      );
    }

    blocTest<CopilotKitBloc, CopilotKitState>(
      'reasoning, activity, raw and custom events leave text intact',
      setUp: () => stubRun(
        (threadId) => [
          RunStartedEvent(threadId: threadId, runId: 'r'),
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
          RunFinishedEvent(threadId: threadId, runId: 'r'),
        ],
      ),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(agent.state.messages.single.content, 'Hello');
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      },
    );

    const runError = RunErrorEvent(message: 'Invalid API key', code: 'AUTH');

    blocTest<CopilotKitBloc, CopilotKitState>(
      'RUN_ERROR ends the run and reports the error once',
      setUp: () => stubRun(
        (threadId) => [
          RunStartedEvent(threadId: threadId, runId: 'r'),
          const TextMessageStartEvent(messageId: 'm1'),
          const TextMessageContentEvent(messageId: 'm1', delta: 'Par'),
          runError,
        ],
      ),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(errors, [same(runError)]);
        expect(agent.state.isRunning, isFalse);
        expect(agent.state.error, same(runError));
        expect(agent.state.messages.single.content, 'Par');
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'unknown_events fixture keeps the text reply',
      setUp: () => stubRun((_) => loadFixture('unknown_events').events),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(
          agent.state.messages.single.content,
          'Hello! Wonderful to meet you.',
        );
        expect(agent.state.isRunning, isFalse);
        expect(errors, isEmpty);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'recorded run_error fixture reports the runtime error',
      setUp: () => stubRun((_) => loadFixture('run_error').events),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
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
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'dropped_connection fixture fails the run and keeps the partial reply',
      setUp: () => stubRun((_) => loadFixture('dropped_connection').events),
      build: () => client,
      act: (_) => client.runAgent(agent),
      verify: (_) {
        expect(errors.single, isA<StateError>());
        expect(agent.state.messages.single.content, 'Hello! Wonderful to');
        expect(agent.state.isRunning, isFalse);
      },
    );
  });
}
