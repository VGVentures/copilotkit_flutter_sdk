import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agentState = CopilotAgentState(agentId: 'default', threadId: 't');

  group(CopilotChatState, () {
    group('fromAgentState', () {
      test('copies isRunning and error', () {
        final state = CopilotChatState.fromAgentState(
          agentState.copyWith(isRunning: true, error: () => 'boom'),
        );

        expect(state, const CopilotChatState(isRunning: true, error: 'boom'));
      });
    });
  });
}
