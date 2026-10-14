import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/tools.dart';

/// {@template agent_snapshot}
/// Immutable view of an agent's state at one point in time.
///
/// `CopilotAgent.changes` emits a new snapshot every time an event changes
/// the agent.
/// {@endtemplate}
class AgentSnapshot {
  /// {@macro agent_snapshot}
  const new({
    this.messages = const [],
    this.state,
    this.isRunning = false,
    this.toolCalls = const [],
    this.error,
  });

  /// Conversation messages, oldest first. The last assistant message grows
  /// while text streams in.
  final List<Message> messages;

  /// Shared agent state (any JSON value), or `null` if the agent sent none.
  final Object? state;

  /// Whether a run is in progress.
  final bool isRunning;

  /// Tool calls made by the agent, in call order.
  final List<ToolCallView> toolCalls;

  /// Error that ended the most recent run, or `null`. Cleared when a new run
  /// starts.
  final Object? error;
}
