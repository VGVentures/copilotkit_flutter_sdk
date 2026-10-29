/// @docImport 'package:copilotkit/src/agent/copilot_agent.dart';
/// @docImport 'package:copilotkit/src/client/client.dart';
/// @docImport 'package:copilotkit/src/tools/tools.dart';
library;

import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/models/run_error.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/messages/models/message.dart';
import 'package:copilotkit/src/messages/models/tool_call.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Immutable view of an agent at one point in time.
///
/// A [CopilotAgent] replaces its state with a new one every time it
/// changes.
class const CopilotAgentState({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,

  /// Id of the conversation thread sent with every run.
  required final String threadId,

  /// Conversation messages, oldest first. The last assistant message grows
  /// while text streams in.
  ///
  /// Unmodifiable in every state the SDK produces; a list passed to this
  /// constructor is kept as it is.
  final List<Message> messages = const [],

  /// State the agent shares with the app, or `null` if neither the agent nor
  /// the app set one.
  ///
  /// Sent as the run's state on every run. Change it from the app with
  /// [CopilotAgent.setSharedState] and [CopilotAgent.patchSharedState]; the
  /// agent changes it with `STATE_SNAPSHOT` and `STATE_DELTA` events.
  final SharedState? sharedState,

  /// Whether the agent is working: from [CopilotKitClient.runAgent] until
  /// the whole turn ends, including frontend tool handlers and the runs that
  /// follow them.
  ///
  /// It stays `true` while a [HumanInTheLoopTool] call waits for the user,
  /// because the turn is still open: [CopilotKitClient.runAgent] does nothing
  /// for the agent until it ends, and the chat bloc ignores sent messages
  /// while it is `true`. Use [awaitingResponseIds] to tell an agent that
  /// waits for the user from one that is streaming, for example to pause the
  /// app's own automatic runs.
  final bool isRunning = false,

  /// Tool calls made by the agent, in call order.
  ///
  /// Unmodifiable in every state the SDK produces; a list passed to this
  /// constructor is kept as it is.
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
  /// Empty unless a [HumanInTheLoopTool] call is awaiting
  /// [CopilotKitClient.respondToToolCall]; see
  /// [ToolCallView.awaitingResponse].
  List<String> get awaitingResponseIds => [
    for (final call in toolCalls)
      if (call.awaitingResponse) call.id,
  ];

  /// The [toolCalls] by id.
  Map<String, ToolCallView> get toolCallsById => {
    for (final call in toolCalls) call.id: call,
  };

  /// The tool calls held by the assistant [messages], in order.
  @internal
  List<ToolCall> get messageToolCalls => [
    for (final message in messages.whereType<AssistantMessage>())
      ...message.toolCalls,
  ];

  /// The results of the tool calls that have a tool message, by tool call
  /// id.
  @internal
  Map<String, String> get toolResults => {
    for (final message in messages.whereType<ToolMessage>())
      message.toolCallId: message.content,
  };

  /// Returns this state with [message] after its [messages].
  @internal
  CopilotAgentState messageAdded(Message message) =>
      copyWith(messages: [...messages, message]);

  /// Returns this state with [messages] as its conversation, and its
  /// [toolCalls] rebuilt from them, so calls that only exist in [messages]
  /// (a loaded history, a resync) render like live ones.
  ///
  /// A call with a tool message is complete, with the message's content as
  /// its result. A call without one keeps its current view (it is still
  /// streaming or executing); one without a view has its full arguments, so
  /// it is executing with the arguments [parse] returns for its raw JSON.
  /// Views that no message holds anymore are dropped.
  @internal
  CopilotAgentState messagesReplaced(
    List<Message> messages, {
    required Map<String, Object?> Function(String arguments) parse,
  }) {
    final known = toolCallsById;
    final replaced = copyWith(messages: messages);
    final results = replaced.toolResults;

    ToolCallView viewFor(ToolCall call) =>
        known[call.id] ??
        ToolCallView(
          id: call.id,
          name: call.name,
          status: ToolCallStatus.executing,
          args: Map.unmodifiable(parse(call.arguments)),
        );

    return replaced.copyWith(
      toolCalls: [
        for (final call in replaced.messageToolCalls)
          if (results[call.id] case final result?)
            viewFor(call).completed(result)
          else
            viewFor(call),
      ],
    );
  }

  /// Returns this state with [delta] appended to the text of the message
  /// [messageId], or with a new message from [role] holding [delta] when
  /// there is no such message yet.
  @internal
  CopilotAgentState textAppended(
    String messageId,
    ag_ui.TextMessageRole role,
    String delta,
  ) {
    final index = messages.lastIndexWhere((m) => m.id == messageId);
    if (index == -1) {
      return messageAdded(
        Message.fromRole(role, id: messageId, content: delta),
      );
    }
    return copyWith(
      messages: [
        ...messages.sublist(0, index),
        messages[index].appended(delta),
        ...messages.sublist(index + 1),
      ],
    );
  }

  /// Returns this state with the text chunk [delta] from [role] appended.
  ///
  /// A chunk without [messageId] continues the last message, but only when
  /// it has the chunk's role, so assistant text never lands in a user
  /// message; otherwise it is dropped. A chunk without [role] is from the
  /// assistant.
  @internal
  CopilotAgentState chunkAppended(
    String? messageId,
    ag_ui.TextMessageRole? role,
    String delta,
  ) {
    final chunkRole = role ?? ag_ui.TextMessageRole.assistant;
    final last = messages.lastOrNull;
    final id =
        messageId ??
        (last != null && last.textRole == chunkRole ? last.id : null);
    if (id == null) return this;
    return textAppended(id, chunkRole, delta);
  }

  /// Returns this state with the new tool call [toolCallId] to the tool
  /// [name], in progress and with no arguments yet.
  ///
  /// The call is added to the assistant message [parentMessageId], or to a
  /// new assistant message when there is none. A repeated [toolCallId] is
  /// dropped, so no two calls share an id.
  @internal
  CopilotAgentState toolCallStarted(
    String toolCallId,
    String name,
    String? parentMessageId,
  ) {
    if (toolCalls.any((view) => view.id == toolCallId)) return this;
    final call = ToolCall(id: toolCallId, name: name, arguments: '');
    final parentIndex = parentMessageId == null
        ? -1
        : messages.lastIndexWhere(
            (m) => m is AssistantMessage && m.id == parentMessageId,
          );
    final view = ToolCallView(
      id: toolCallId,
      name: name,
      status: ToolCallStatus.inProgress,
    );
    if (parentIndex == -1) {
      return copyWith(
        messages: [
          ...messages,
          AssistantMessage(
            id: parentMessageId ?? toolCallId,
            toolCalls: List.unmodifiable([call]),
          ),
        ],
        toolCalls: [...toolCalls, view],
      );
    }
    final parent = messages[parentIndex] as AssistantMessage;
    return copyWith(
      messages: [
        ...messages.sublist(0, parentIndex),
        parent.toolCallAdded(call),
        ...messages.sublist(parentIndex + 1),
      ],
      toolCalls: [...toolCalls, view],
    );
  }

  /// Returns this state with [delta] appended to the raw arguments of the
  /// tool call [toolCallId], and the arguments [parse] returns for them on
  /// its view.
  @internal
  CopilotAgentState toolArgumentsAppended(
    String toolCallId,
    String delta, {
    required Map<String, Object?> Function(String arguments) parse,
  }) {
    final call = messageToolCalls.where((c) => c.id == toolCallId).lastOrNull;
    if (call == null) return this;
    final updated = call.copyWith(arguments: call.arguments + delta);
    return copyWith(
      messages: [
        for (final message in messages)
          if (message is AssistantMessage && message.anyToolCall(toolCallId))
            message.toolCallReplaced(updated)
          else
            message,
      ],
    ).toolCallUpdated(
      toolCallId,
      (view) => view.copyWith(args: Map.unmodifiable(parse(updated.arguments))),
    );
  }

  /// Returns this state with the result [content] of the tool call
  /// [toolCallId], as the tool message [messageId], and the call complete.
  ///
  /// A repeated [messageId] is dropped.
  @internal
  CopilotAgentState toolCallCompleted(
    String messageId,
    String toolCallId,
    String content,
  ) {
    if (messages.any((m) => m is ToolMessage && m.id == messageId)) {
      return this;
    }
    return messageAdded(
      ToolMessage(id: messageId, toolCallId: toolCallId, content: content),
    ).toolCallUpdated(toolCallId, (view) => view.completed(content));
  }

  /// Returns this state with every tool call in progress marked executing.
  ///
  /// Calls streamed as chunks have no end event; once the run finishes
  /// their arguments are complete.
  @internal
  CopilotAgentState toolCallsMarkedExecuting() {
    if (!toolCalls.any((view) => view.isInProgress)) return this;
    return copyWith(
      toolCalls: [for (final view in toolCalls) view.markedExecuting()],
    );
  }

  /// Returns this state with the view of the tool call [toolCallId]
  /// replaced by what [update] returns for it, or this state when there is
  /// no such call or [update] doesn't change it.
  @internal
  CopilotAgentState toolCallUpdated(
    String toolCallId,
    ToolCallView Function(ToolCallView view) update,
  ) {
    final index = toolCalls.indexWhere((view) => view.id == toolCallId);
    if (index == -1) return this;
    final view = toolCalls[index];
    final updated = update(view);
    if (updated == view) return this;
    return copyWith(
      toolCalls: [
        ...toolCalls.sublist(0, index),
        updated,
        ...toolCalls.sublist(index + 1),
      ],
    );
  }

  /// Returns this state with the shared state replaced by the JSON object
  /// [json], or cleared when [json] is `null`.
  @internal
  CopilotAgentState sharedStateReplaced(Map<String, Object?>? json) => copyWith(
    sharedState: () =>
        json == null ? null : SharedState(Map.unmodifiable(json)),
  );

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
  /// The lists passed as [messages] and [toolCalls] are copied into
  /// unmodifiable lists, so a state the SDK produces can't be changed in
  /// place.
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
