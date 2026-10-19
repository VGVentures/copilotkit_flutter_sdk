import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/agent/copilot_agent_event.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

/// A [CopilotAgent] whose client is a mock, for driving the bloc directly.
CopilotAgent testAgent() =>
    CopilotAgent(agentId: 'default', client: _MockCopilotKitClient());

/// Applies [event] to an agent seeded with [initial] and returns its state.
///
/// Goes through the bloc, so the result is what a consumer would observe.
Future<AgentState> reduce(AgentState initial, BaseEvent event) =>
    replay([event], initial);

/// Applies [events] in order to an agent seeded with [initial] and returns
/// its final state.
Future<AgentState> replay(
  List<BaseEvent> events, [
  AgentState initial = const AgentState(),
]) async {
  final agent = testAgent()..emit(initial);
  for (final event in events) {
    agent.add(AgentEventReceived(event));
  }
  await agent.settled;
  final state = agent.state;
  await agent.close();
  return state;
}
