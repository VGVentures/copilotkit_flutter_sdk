import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';

/// Initial state of the agents built by [buildAgent].
const agentState = CopilotAgentState(agentId: 'default', threadId: 'thread-1');

/// An agent in [agentState], for driving the bloc directly.
CopilotAgentBloc buildAgent() =>
    CopilotAgentBloc(agentId: 'default', threadId: 'thread-1');

/// Shortcuts for adding AG-UI events to a [CopilotAgentBloc] in tests.
extension CopilotAgentBlocX on CopilotAgentBloc {
  /// Adds each of [events], in order, as an [AgentEventReceived].
  void receive(List<BaseEvent> events) {
    for (final event in events) {
      add(AgentEventReceived(event));
    }
  }
}
