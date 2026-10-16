import 'package:copilotkit/src/agent/copilot_agent.dart';
import 'package:copilotkit/src/context/agent_context_entry.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:equatable/equatable.dart';

/// What a `CopilotKitClient` holds: the agents it opened, the registered
/// frontend tools and the context entries sent with every run.
class const CopilotKitState({
  /// Open agents by agent id; see `AgentOpened`.
  final Map<String, CopilotAgent> agents = const {},

  /// Registered tools by name; see `ToolRegistered`.
  final Map<String, FrontendTool> tools = const {},

  /// Context entries in insertion order; see `ContextAdded`.
  final List<AgentContextEntry> context = const [],
}) extends Equatable {
  /// Creates the state of a client.
  this;

  /// Returns a copy with the given fields replaced.
  CopilotKitState copyWith({
    Map<String, CopilotAgent>? agents,
    Map<String, FrontendTool>? tools,
    List<AgentContextEntry>? context,
  }) {
    return CopilotKitState(
      agents: agents ?? this.agents,
      tools: tools ?? this.tools,
      context: context ?? this.context,
    );
  }

  @override
  List<Object?> get props => [agents, tools, context];
}
