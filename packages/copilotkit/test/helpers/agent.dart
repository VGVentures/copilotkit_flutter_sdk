import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';

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

/// Applies [events] to [from] one at a time with an [AgentEventReducer].
///
/// Returns the states that changed, in order, like an agent emits them, and
/// the final state.
({List<CopilotAgentState> states, CopilotAgentState state}) reduce(
  List<BaseEvent> events, {
  CopilotAgentState from = agentState,
}) {
  const reducer = AgentEventReducer();
  final states = <CopilotAgentState>[];
  var state = from;
  for (final event in events) {
    final next = reducer.reduce(state, event);
    if (next == state) continue;
    states.add(state = next);
  }
  return (states: states, state: state);
}
