import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:equatable/equatable.dart';

/// Immutable view of an agent at one point in time.
///
/// `CopilotAgent.stream` emits a new state every time an event changes the
/// agent.
class const AgentState({
  /// Conversation messages, oldest first. The last assistant message grows
  /// while text streams in.
  final List<Message> messages = const [],

  /// Shared agent state (any JSON value), or `null` if the agent sent none.
  final Object? sharedState,

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
}) extends Equatable {
  /// Creates the state of an agent.
  this;

  @override
  List<Object?> get props => [
    messages,
    sharedState,
    isRunning,
    toolCalls,
    error,
  ];

  /// Returns a copy with the given fields replaced.
  ///
  /// [sharedState] and [error] are getters so a caller can set a value
  /// (`error: () => e`), clear it (`error: () => null`) or leave it alone by
  /// not passing it.
  AgentState copyWith({
    List<Message>? messages,
    Object? Function()? sharedState,
    bool? isRunning,
    List<ToolCallView>? toolCalls,
    Object? Function()? error,
  }) {
    return AgentState(
      messages: messages ?? this.messages,
      sharedState: sharedState == null ? this.sharedState : sharedState(),
      isRunning: isRunning ?? this.isRunning,
      toolCalls: toolCalls ?? this.toolCalls,
      error: error == null ? this.error : error(),
    );
  }
}
