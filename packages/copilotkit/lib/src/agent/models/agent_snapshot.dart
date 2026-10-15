import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';

/// Immutable view of an agent's state at one point in time.
///
/// `CopilotAgent.changes` emits a new snapshot every time an event changes
/// the agent.
class const AgentSnapshot({
  /// Conversation messages, oldest first. The last assistant message grows
  /// while text streams in.
  final List<Message> messages = const [],

  /// Shared agent state (any JSON value), or `null` if the agent sent none.
  final Object? state,

  /// Whether the agent is working: from `run()` until the whole turn ends,
  /// including frontend tool handlers and the runs that follow them.
  final bool isRunning = false,

  /// Tool calls made by the agent, in call order.
  final List<ToolCallView> toolCalls = const [],

  /// Error that ended the most recent run, or `null`. Cleared when a new run
  /// starts.
  ///
  /// A [RunErrorEvent] when the runtime reported the error; otherwise the
  /// transport or client error.
  final Object? error,
}) {
  /// Creates a snapshot of an agent's state.
  this;

  /// Returns a copy with the given fields replaced.
  ///
  /// [state] and [error] are getters so a caller can set a value
  /// (`error: () => e`), clear it (`error: () => null`) or leave it alone by
  /// not passing it.
  AgentSnapshot copyWith({
    List<Message>? messages,
    Object? Function()? state,
    bool? isRunning,
    List<ToolCallView>? toolCalls,
    Object? Function()? error,
  }) {
    return AgentSnapshot(
      messages: messages ?? this.messages,
      state: state == null ? this.state : state(),
      isRunning: isRunning ?? this.isRunning,
      toolCalls: toolCalls ?? this.toolCalls,
      error: error == null ? this.error : error(),
    );
  }
}
