import 'package:copilotkit/copilotkit.dart';

/// Method-shaped shortcuts for driving a [CopilotKitClient] in tests.
///
/// Each one adds the event and waits for its handler, so the next line can
/// read the client's or the agent's state.
extension CopilotKitClientX on CopilotKitClient {
  /// Opens and returns the agent [agentId].
  Future<CopilotAgent> openAgent(String agentId) async {
    await handled(AgentOpened(agentId));
    return state.agents[agentId]!;
  }

  /// Runs [agent] and returns once the whole turn has ended.
  Future<void> runAgent(CopilotAgent agent) async {
    await handled(AgentRunRequested(agent.agentId));
  }

  /// Stops [agent] and returns once the stop has been handled.
  Future<void> stopAgent(CopilotAgent agent) async {
    await handled(AgentStopRequested(agent.agentId));
  }

  /// Registers [tool].
  Future<void> registerTool(FrontendTool tool) async {
    await handled(ToolRegistered(tool));
  }

  /// Unregisters [tool].
  Future<void> unregisterTool(FrontendTool tool) async {
    await handled(ToolUnregistered(tool));
  }

  /// Adds [entry] to the context.
  Future<void> addContext(AgentContextEntry entry) async {
    await handled(ContextAdded(entry));
  }
}
