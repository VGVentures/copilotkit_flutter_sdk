import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/agent/mappers/agent_event_mapper.dart';

/// Initial state of the agents built by [buildAgent].
const agentState = CopilotKitAgentState(
  agentId: 'default',
  threadId: 'thread-1',
);

/// An agent in [agentState].
CopilotKitAgent buildAgent() =>
    CopilotKitAgent(agentId: 'default', threadId: 'thread-1');

/// Applies [events] to [from] one at a time with an [AgentEventMapper].
///
/// Returns the states that changed, in order, like an agent emits them, and
/// the final state.
({List<CopilotKitAgentState> states, CopilotKitAgentState state}) mapEvents(
  List<BaseEvent> events, {
  CopilotKitAgentState from = agentState,
}) {
  const mapper = AgentEventMapper();
  final states = <CopilotKitAgentState>[];
  var state = from;
  for (final event in events) {
    final next = mapper(state, event);
    if (next == state) continue;
    states.add(state = next);
  }
  return (states: states, state: state);
}
