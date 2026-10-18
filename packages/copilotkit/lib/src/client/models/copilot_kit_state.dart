import 'package:copilotkit/src/agent/copilot_agent.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:copilotkit/src/context/agent_context_entry.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What a `CopilotKitClient` holds: the agents it opened, the registered
/// frontend tools, the context entries sent with every run and the turns in
/// progress.
class const CopilotKitState({
  /// Open agents by agent id; see `AgentOpened`.
  final Map<String, CopilotAgent> agents = const {},

  /// Every registration of each tool name, the last one active; see
  /// `ToolRegistered`. Internal: read the active ones through [tools].
  @internal final Map<String, List<FrontendTool>> registrations = const {},

  /// Context entries in insertion order; see `ContextAdded`.
  final List<AgentContextEntry> context = const [],

  /// Turns in progress by agent id; see `AgentRunRequested`.
  final Map<String, TurnState> turns = const {},
}) extends Equatable {
  /// Creates the state of a client.
  this;

  /// Registered tools by name; see `ToolRegistered`. Of several registrations
  /// of a name, the last one is active.
  Map<String, FrontendTool> get tools => {
    for (final MapEntry(:key, :value) in registrations.entries) key: value.last,
  };

  /// Returns a copy with the given fields replaced.
  CopilotKitState copyWith({
    Map<String, CopilotAgent>? agents,
    Map<String, List<FrontendTool>>? registrations,
    List<AgentContextEntry>? context,
    Map<String, TurnState>? turns,
  }) {
    return CopilotKitState(
      agents: agents ?? this.agents,
      registrations: registrations ?? this.registrations,
      context: context ?? this.context,
      turns: turns ?? this.turns,
    );
  }

  @override
  List<Object?> get props => [agents, registrations, context, turns];
}
