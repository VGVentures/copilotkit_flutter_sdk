import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotAgentEvent, () {
    test('supports value equality', () {
      final user = UserMessage(id: 'u1', content: 'Hi');
      final event = RunStartedEvent(threadId: 't', runId: 'r');
      final completer = Completer<void>();

      expect(AgentEventReceived(event), AgentEventReceived(event));
      expect(AgentMessageAdded(user), AgentMessageAdded(user));
      expect(AgentMessagesSet([user]), AgentMessagesSet([user]));
      expect(AgentMessagesSet([user]), isNot(const AgentMessagesSet([])));
      expect(const AgentStateSet({'a': 1}), const AgentStateSet({'a': 1}));
      expect(const AgentStateSet({'a': 1}), isNot(const AgentStateSet(null)));
      expect(
        const AgentStatePatched([
          {'op': 'remove', 'path': '/a'},
        ]),
        const AgentStatePatched([
          {'op': 'remove', 'path': '/a'},
        ]),
      );
      expect(
        const AgentStatePatched([
          {'op': 'remove', 'path': '/a'},
        ]),
        isNot(const AgentStatePatched([])),
      );
      // Non-const instances, so equality goes through props.
      // ignore: prefer_const_constructors
      expect(AgentTurnStarted(), AgentTurnStarted());
      // Same reason as above.
      // ignore: prefer_const_constructors
      expect(AgentTurnEnded(), AgentTurnEnded());
      expect(
        const AgentToolCallAwaiting('c1'),
        const AgentToolCallAwaiting('c1'),
      );
      expect(
        const AgentToolCallAwaiting('c1'),
        isNot(const AgentToolCallAwaiting('c2')),
      );
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
