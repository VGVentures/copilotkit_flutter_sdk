/// @docImport 'package:copilotkit/src/agent/copilotkit_agent.dart';
/// @docImport 'package:copilotkit/src/client/copilotkit_client.dart';
/// @docImport 'package:copilotkit/src/tools/client_tool.dart';
library;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:equatable/equatable.dart';

/// Immutable view of an agent at one point in time.
///
/// A [CopilotKitAgent] replaces its state with a new one every time it
/// changes.
class const CopilotKitAgentState({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,

  /// Id of the conversation thread sent with every run.
  required final String threadId,

  /// Conversation messages, oldest first.
  ///
  /// The last assistant message grows while text streams in.
  final List<Message> messages = const [],

  /// State the agent shares with the app, or `null` if neither the agent nor
  /// the app set one.
  ///
  /// Sent as [RunAgentInput.state] on every run. Change it from the app with
  /// [CopilotKitAgent.setSharedState] and [CopilotKitAgent.patchSharedState];
  /// the agent changes it with `STATE_SNAPSHOT` and `STATE_DELTA` events.
  /// Debug builds of `ag_ui` assert that it is a JSON object (a [Map]) or
  /// `null` when a run is sent.
  final SharedState? sharedState,

  /// Whether the agent is working: from [CopilotKitClient.runAgent] until
  /// the whole turn ends, including frontend tool handlers and the runs that
  /// follow them.
  ///
  /// It stays `true` while a [HumanInTheLoopTool] call waits for the user,
  /// because the turn is still open: [CopilotKitClient.runAgent] does nothing
  /// for the agent until it ends. Use [awaitingResponseIds] to tell an agent
  /// that waits for the user from one that is streaming, for example to pause
  /// the app's own automatic runs.
  final bool isRunning = false,

  /// Tool calls made by the agent, in call order.
  final List<ToolCallView> toolCalls = const [],

  /// Error that ended the most recent run, or `null`.
  ///
  /// Cleared when a new run starts.
  ///
  /// A [RunErrorEvent] when the runtime reported the error; otherwise the
  /// transport or client error.
  final Object? error,
}) extends Equatable {
  /// Creates the state of an agent.
  this;

  /// Ids of the tool calls that wait for the user's answer, in call order.
  ///
  /// Empty unless a [HumanInTheLoopTool] call is awaiting
  /// [CopilotKitClient.respondToToolCall]; see
  /// [ToolCallView.awaitingResponse].
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
  /// [sharedState] and [error] are callbacks so a caller can set a value
  /// (`error: () => e`), clear it (`error: () => null`) or leave it alone by
  /// not passing it.
  ///
  /// The [messages] and [toolCalls] given are copied into unmodifiable
  /// lists, so the state can't change behind an agent's back.
  CopilotKitAgentState copyWith({
    List<Message>? messages,
    SharedState? Function()? sharedState,
    bool? isRunning,
    List<ToolCallView>? toolCalls,
    Object? Function()? error,
  }) {
    return CopilotKitAgentState(
      agentId: agentId,
      threadId: threadId,
      messages: messages == null ? this.messages : List.unmodifiable(messages),
      sharedState: sharedState == null ? this.sharedState : sharedState(),
      isRunning: isRunning ?? this.isRunning,
      toolCalls: toolCalls == null
          ? this.toolCalls
          : List.unmodifiable(toolCalls),
      error: error == null ? this.error : error(),
    );
  }
}
