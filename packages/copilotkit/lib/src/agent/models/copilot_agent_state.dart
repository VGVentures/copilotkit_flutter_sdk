import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/run_error.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:equatable/equatable.dart';

/// Immutable view of an agent at one point in time.
///
/// A `CopilotAgent` replaces its state with a new one every time it
/// changes.
class const CopilotAgentState({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,

  /// Id of the conversation thread sent with every run.
  required final String threadId,

  /// Conversation messages, oldest first. The last assistant message grows
  /// while text streams in.
  final List<Message> messages = const [],

  /// State the agent shares with the app, or `null` if neither the agent nor
  /// the app set one.
  ///
  /// Sent as `RunAgentInput.state` on every run. Change it from the app with
  /// `CopilotAgent.setSharedState` and `CopilotAgent.patchSharedState`; the
  /// agent changes it with `STATE_SNAPSHOT` and `STATE_DELTA` events. Debug
  /// builds of `ag_ui` assert that it is a JSON object (a `Map`) or `null`
  /// when a run is sent.
  final SharedState? sharedState,

  /// Whether the agent is working: from `CopilotKitClient.runAgent` until
  /// the whole turn ends, including frontend tool handlers and the runs that
  /// follow them.
  ///
  /// It stays `true` while a `HumanInTheLoopTool` call waits for the user,
  /// because the turn is still open: `CopilotKitClient.runAgent` does nothing
  /// for the agent until it ends, and the chat bloc ignores sent messages
  /// while it is `true`. Use [awaitingResponseIds] to tell an agent that
  /// waits for the user from one that is streaming, for example to pause the
  /// app's own automatic runs.
  final bool isRunning = false,

  /// Tool calls made by the agent, in call order.
  final List<ToolCallView> toolCalls = const [],

  /// Error that ended the most recent run, or `null`. Cleared when a new run
  /// starts.
  ///
  /// A [RunError] when the runtime reported the error; otherwise the
  /// transport or client error.
  final Object? error,
}) extends Equatable {
  /// Creates the state of an agent.
  this;

  /// Ids of the tool calls that wait for the user's answer, in call order.
  ///
  /// Empty unless a `HumanInTheLoopTool` call is awaiting
  /// `CopilotKitClient.respondToToolCall`; see
  /// `ToolCallView.awaitingResponse`.
  List<String> get awaitingResponseIds => [
    for (final call in toolCalls)
      if (call.awaitingResponse) call.id,
  ];

  @override
  List<Object?> get props => [
    agentId,
    threadId,
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
  CopilotAgentState copyWith({
    List<Message>? messages,
    SharedState? Function()? sharedState,
    bool? isRunning,
    List<ToolCallView>? toolCalls,
    Object? Function()? error,
  }) {
    return CopilotAgentState(
      agentId: agentId,
      threadId: threadId,
      messages: messages ?? this.messages,
      sharedState: sharedState == null ? this.sharedState : sharedState(),
      isRunning: isRunning ?? this.isRunning,
      toolCalls: toolCalls ?? this.toolCalls,
      error: error == null ? this.error : error(),
    );
  }
}
