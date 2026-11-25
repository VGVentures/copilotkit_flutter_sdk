import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/recording_client.dart';

class _MockCopilotAgent extends Mock implements CopilotAgent;

void main() {
  group(CopilotAction, () {
    late RecordingClient client;
    late int taps;

    setUp(() {
      client = RecordingClient();
      taps = 0;
    });

    List<Object?> clicks() => [
      for (final call in client.calls)
        if (call.method == 'recordTrajectoryEvent' &&
            call.arguments.first == TrajectoryBuiltInEvent.click)
          call.arguments.last,
    ];

    Widget button() => CopilotAction(
      name: 'approve',
      child: ElevatedButton(
        onPressed: () => taps++,
        child: const Text('Approve'),
      ),
    );

    testWidgets('records a tap and lets the child handle it', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(home: Scaffold(body: button())),
        ),
      );

      await tester.tap(find.text('Approve'));

      expect(taps, 1);
      expect(clicks(), [
        {
          'target': {
            'tag': 'CopilotAction',
            'action': 'approve',
            'input': 'pointer',
          },
          'route': '/',
        },
      ]);
    });

    testWidgets('adds the tool call and the agent around it', (tester) async {
      final agent = _MockCopilotAgent();
      when(() => agent.state).thenReturn(
        const CopilotAgentState(agentId: 'default', threadId: 'thread-1'),
      );
      when(() => agent.stream).thenAnswer((_) => const Stream.empty());
      final kit = _AgentClient(client, agent);
      await tester.pumpWidget(
        CopilotKit.value(
          client: kit,
          child: MaterialApp(
            home: Scaffold(
              body: CopilotAgentScope(
                agentId: 'default',
                child: ToolRenderer(
                  name: 'confirm',
                  builder: (context, call) => button(),
                  child: ToolCallWidget(
                    call: const ToolCallView(
                      id: 'c1',
                      name: 'confirm',
                      status: ToolCallStatus.executing,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Approve'));

      expect(clicks().single, {
        'target': {
          'tag': 'CopilotAction',
          'action': 'approve',
          'input': 'pointer',
        },
        'route': '/',
        'agentId': 'default',
        'threadId': 'thread-1',
        'toolCallId': 'c1',
        'toolName': 'confirm',
        'toolStatus': 'executing',
      });
    });

    testWidgets('records nothing for a drag', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: Scaffold(body: Center(child: button())),
          ),
        ),
      );

      await tester.drag(find.text('Approve'), const Offset(0, 100));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Approve')),
      );
      await gesture.cancel();

      expect(clicks(), isEmpty);
    });

    testWidgets('records nothing without a CopilotKit', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: button())));

      await tester.tap(find.text('Approve'));

      expect(taps, 1);
    });
  });
}

/// The recording client, opening [agent] for the agent scope.
class _AgentClient extends RecordingClient {
  new(this._recorder, this._agent);

  final RecordingClient _recorder;
  final CopilotAgent _agent;

  @override
  List<ClientCall> get calls => _recorder.calls;

  @override
  CopilotAgent agent(String agentId, {String? threadId}) => _agent;
}
