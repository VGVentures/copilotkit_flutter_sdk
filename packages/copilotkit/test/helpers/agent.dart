import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/agent/agent_event_mapper.dart';

/// Initial state of the agents built by [buildAgent].
const agentState = CopilotAgentState(agentId: 'default', threadId: 'thread-1');

/// An agent in [agentState].
CopilotAgent buildAgent() =>
    CopilotAgent(agentId: 'default', threadId: 'thread-1');

/// Applies [events] to [from] one at a time with an [AgentEventMapper].
///
/// Returns the states that changed, in order, like an agent emits them, and
/// the final state.
({List<CopilotAgentState> states, CopilotAgentState state}) mapEvents(
  List<ag_ui.BaseEvent> events, {
  CopilotAgentState from = agentState,
}) {
  const mapper = AgentEventMapper();
  final states = <CopilotAgentState>[];
  var state = from;
  for (final event in events) {
    final next = mapper(state, event);
    if (next == state) continue;
    states.add(state = next);
  }
  return (states: states, state: state);
}
