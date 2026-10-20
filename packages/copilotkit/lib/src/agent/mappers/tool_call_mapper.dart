import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/extensions/copilotkit_agent_state_tool_calls.dart';
import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';

/// Applies AG-UI tool call events to a [CopilotKitAgentState].
///
/// Keeps each tool call in two places in step: the [ToolCall] on its
/// assistant message, sent back to the runtime, and the [ToolCallView] the
/// app renders.
///
/// Pure: [CopilotKitAgentState]s are never mutated, and events that don't
/// change the agent return the given snapshot itself.
class const ToolCallMapper({
  /// Parses the streamed arguments of tool calls.
  final PartialJsonParser _parser = const PartialJsonParser(),
}) {
  /// Creates a tool call mapper.
  this;

  /// [snapshot] with [messages] as its conversation, and its tool calls
  /// rebuilt from them, so calls that only exist in [messages] (a loaded
  /// history, a resync) render like live ones.
  CopilotKitAgentState replaceMessages(
    CopilotKitAgentState snapshot,
    List<Message> messages,
  ) => snapshot.copyWith(
    messages: messages,
    toolCalls: _toolCallsOf(messages, snapshot.toolCalls),
  );

  /// [snapshot] with call [toolCallId] added to message [parentMessageId],
  /// or to a new assistant message when there's no such message.
  ///
  /// A call that already exists is ignored.
  CopilotKitAgentState start(
    CopilotKitAgentState snapshot,
    String toolCallId,
    String name,
    String? parentMessageId,
  ) {
    if (snapshot.toolCalls.any((view) => view.id == toolCallId)) {
      return snapshot;
    }
    final call = ToolCall(
      id: toolCallId,
      function: FunctionCall(name: name, arguments: ''),
    );
    return snapshot.copyWith(
      messages: snapshot.messages.withToolCall(call, parentMessageId),
      toolCalls: [
        ...snapshot.toolCalls,
        ToolCallView(
          id: toolCallId,
          name: name,
          status: ToolCallStatus.inProgress,
        ),
      ],
    );
  }

  /// Appends [delta] to the raw arguments of call [toolCallId] and updates
  /// its view with the arguments parsed so far.
  CopilotKitAgentState appendArgs(
    CopilotKitAgentState snapshot,
    String toolCallId,
    String delta,
  ) {
    final call = snapshot.messages.toolCall(toolCallId);
    if (call == null) return snapshot;
    final arguments = call.function.arguments + delta;
    final updatedCall = call.copyWith(
      function: call.function.copyWith(arguments: arguments),
    );
    final args = _parser.parse(arguments);
    return snapshot
        .copyWith(
          messages: snapshot.messages.replacingToolCall(call, updatedCall),
        )
        .updateToolCall(toolCallId, (view) => view.copyWith(args: args));
  }

  /// [snapshot] with call [toolCallId] executing, as its arguments are
  /// complete.
  CopilotKitAgentState end(CopilotKitAgentState snapshot, String toolCallId) =>
      snapshot.updateToolCall(toolCallId, (view) => view.finishArgs());

  /// Applies a chunk [event], starting its call when it's new.
  ///
  /// A chunk without a call id continues the last call.
  CopilotKitAgentState applyChunk(
    CopilotKitAgentState snapshot,
    ToolCallChunkEvent event,
  ) {
    final id = event.toolCallId ?? snapshot.toolCalls.lastOrNull?.id;
    if (id == null) return snapshot;
    var next = snapshot;
    if (!next.toolCalls.any((view) => view.id == id)) {
      final name = event.toolCallName;
      if (name == null) return snapshot;
      next = start(next, id, name, event.parentMessageId);
    }
    final delta = event.delta;
    return delta == null ? next : appendArgs(next, id, delta);
  }

  /// [snapshot] with the tool message [messageId] holding [content] appended,
  /// and call [toolCallId] complete with [content] as its result.
  ///
  /// A tool message that already exists is ignored.
  CopilotKitAgentState complete(
    CopilotKitAgentState snapshot,
    String messageId,
    String toolCallId,
    String content,
  ) {
    if (snapshot.messages.any((m) => m is ToolMessage && m.id == messageId)) {
      return snapshot;
    }
    return snapshot
        .copyWith(
          messages: [
            ...snapshot.messages,
            ToolMessage(
              id: messageId,
              toolCallId: toolCallId,
              content: content,
            ),
          ],
        )
        .updateToolCall(toolCallId, (view) => view.complete(content));
  }

  /// [snapshot] with every call still streaming its arguments executing.
  ///
  /// Calls streamed as chunks have no End event; once the run finishes their
  /// arguments are complete.
  CopilotKitAgentState finishArgs(CopilotKitAgentState snapshot) {
    if (!snapshot.toolCalls.any((v) => v.status == ToolCallStatus.inProgress)) {
      return snapshot;
    }
    return snapshot.copyWith(
      toolCalls: [for (final view in snapshot.toolCalls) view.finishArgs()],
    );
  }

  /// The tool calls held by the assistant messages in [messages], in order.
  ///
  /// A call with a tool message is complete, with the message's content as
  /// its result. A call without one keeps its view in [known] (it is still
  /// streaming or executing); one that isn't known has its full arguments,
  /// so it is executing. Views in [known] that no message holds anymore are
  /// dropped.
  List<ToolCallView> _toolCallsOf(
    List<Message> messages,
    List<ToolCallView> known,
  ) {
    final results = messages.toolResults;
    final knownById = {for (final view in known) view.id: view};
    return [
      for (final call in messages.toolCalls)
        switch ((
          knownById[call.id] ?? _executingView(call),
          results[call.id],
        )) {
          (final view, final result?) => view.complete(result),
          (final view, null) => view,
        },
    ];
  }

  /// A view of [call], whose arguments are complete, so it is executing.
  ToolCallView _executingView(ToolCall call) => ToolCallView(
    id: call.id,
    name: call.function.name,
    status: ToolCallStatus.executing,
    args: _parser.parse(call.function.arguments),
  );
}

extension on List<Message> {
  /// The tool calls held by the assistant messages, in order.
  Iterable<ToolCall> get toolCalls => whereType<AssistantMessage>().expand(
    (message) => message.toolCalls ?? const <ToolCall>[],
  );

  /// The content of each tool message, by the id of the call it answers.
  Map<String, String> get toolResults => {
    for (final message in whereType<ToolMessage>())
      message.toolCallId: message.content,
  };

  /// The last tool call [id] held by an assistant message, if any.
  ToolCall? toolCall(String id) =>
      toolCalls.where((call) => call.id == id).lastOrNull;

  /// These messages with [call] added to the last assistant message
  /// [parentMessageId], or to a new assistant message when there's none.
  List<Message> withToolCall(ToolCall call, String? parentMessageId) {
    final parentIndex = parentMessageId == null
        ? -1
        : lastIndexWhere(
            (m) => m is AssistantMessage && m.id == parentMessageId,
          );
    if (parentIndex == -1) {
      return [
        ...this,
        AssistantMessage(id: parentMessageId ?? call.id, toolCalls: [call]),
      ];
    }
    final parent = this[parentIndex] as AssistantMessage;
    return [
      ...this,
    ]..[parentIndex] = parent.copyWith(toolCalls: [...?parent.toolCalls, call]);
  }

  /// These messages with [call] replaced by [replacement] in the assistant
  /// message that holds it.
  List<Message> replacingToolCall(ToolCall call, ToolCall replacement) => [
    for (final message in this)
      if (message is AssistantMessage &&
          (message.toolCalls?.contains(call) ?? false))
        message.copyWith(
          toolCalls: [
            for (final c in message.toolCalls!)
              // ag_ui models don't override `==`, so this matches the
              // ToolCall itself, not another one with the same fields.
              if (c == call) replacement else c,
          ],
        )
      else
        message,
  ];
}
