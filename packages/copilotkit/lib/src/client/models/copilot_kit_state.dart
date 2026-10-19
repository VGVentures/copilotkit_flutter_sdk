import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:copilotkit/src/context/agent_context_entry.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:equatable/equatable.dart';

/// What a `CopilotKitClient` holds: the agents it opened, the registered
/// frontend tools, the context entries sent with every run and the turns in
/// progress.
class const CopilotKitState({
  /// Open agents by agent id; see `AgentOpened`.
  final Map<String, CopilotAgentBloc> agents = const {},

  /// Registered tools by name; see `ToolRegistered`.
  final Map<String, FrontendTool> tools = const {},

  /// Context entries in insertion order; see `ContextAdded`.
  final List<AgentContextEntry> context = const [],

  /// Turns in progress by agent id; see `AgentRunRequested`.
  ///
  /// Internal bookkeeping of the client: read `CopilotAgentState.isRunning`
  /// to know whether an agent is working.
  final Map<String, TurnState> turns = const {},
}) extends Equatable {
  /// Creates the state of a client.
  this;

  /// Returns a copy with the given fields replaced.
  CopilotKitState copyWith({
    Map<String, CopilotAgentBloc>? agents,
    Map<String, FrontendTool>? tools,
    List<AgentContextEntry>? context,
    Map<String, TurnState>? turns,
  }) {
    return CopilotKitState(
      agents: agents ?? this.agents,
      tools: tools ?? this.tools,
      context: context ?? this.context,
      turns: turns ?? this.turns,
    );
  }

  @override
  List<Object?> get props => [agents, tools, context, turns];
}
