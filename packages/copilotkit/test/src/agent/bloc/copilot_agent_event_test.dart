import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotAgentEvent, () {
    test('supports value equality', () {
      final user = UserMessage(id: 'u1', content: 'Hi');
      final event = RunStartedEvent(threadId: 't', runId: 'r');
      final completer = Completer<void>();

      expect(AgentEventReceived(event), AgentEventReceived(event));
      expect(AgentMessageAdded(user), AgentMessageAdded(user));
      // Non-const instances, so equality goes through props.
      // ignore: prefer_const_constructors
      expect(AgentTurnStarted(), AgentTurnStarted());
      // Same reason as above.
      // ignore: prefer_const_constructors
      expect(AgentTurnEnded(), AgentTurnEnded());
      expect(const AgentRunFailed('boom'), const AgentRunFailed('boom'));
      expect(const AgentRunFailed('boom'), isNot(const AgentRunFailed('x')));
      expect(AgentSettleRequested(completer), AgentSettleRequested(completer));
      expect(
        AgentSettleRequested(completer),
        isNot(AgentSettleRequested(Completer<void>())),
      );
    });
  });
}
