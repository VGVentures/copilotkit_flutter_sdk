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

  /// Whether the agent is working: from `run()` until the whole turn ends,
  /// including frontend tool handlers and the runs that follow them.
  final bool isRunning;

  /// Tool calls made by the agent, in call order.
  final List<ToolCallView> toolCalls;

  /// Error that ended the most recent run, or `null`. Cleared when a new run
  /// starts.
  ///
  /// A [RunErrorEvent] when the runtime reported the error; otherwise the
  /// transport or client error.
  final Object? error;

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass `null` for [state] or [error] to clear them.
  AgentSnapshot copyWith({
    List<Message>? messages,
    Object? state = _unset,
    bool? isRunning,
    List<ToolCallView>? toolCalls,
    Object? error = _unset,
  }) {
    return AgentSnapshot(
      messages: messages ?? this.messages,
      state: identical(state, _unset) ? this.state : state,
      isRunning: isRunning ?? this.isRunning,
      toolCalls: toolCalls ?? this.toolCalls,
      error: identical(error, _unset) ? this.error : error,
    );
  }
}

const Object _unset = Object();
