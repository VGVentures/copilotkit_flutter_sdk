import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_snapshot.dart';
import 'package:copilotkit/src/json_patch.dart';
import 'package:copilotkit/src/partial_json.dart';
import 'package:copilotkit/src/tools.dart';

/// Applies [event] to [snapshot] and returns the resulting snapshot.
///
/// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
/// don't change the agent return [snapshot] itself, so callers can skip
/// emitting when `identical(previous, next)`.
AgentSnapshot reduceAgentEvent(AgentSnapshot snapshot, BaseEvent event) {
  return switch (event) {
    RunStartedEvent() => snapshot.copyWith(isRunning: true, error: null),
    RunFinishedEvent() => _finishToolArgs(snapshot.copyWith(isRunning: false)),
    RunErrorEvent() => snapshot.copyWith(isRunning: false, error: event),
    TextMessageStartEvent(:final messageId, :final role, :final name) =>
      snapshot.copyWith(
        messages: [
          ...snapshot.messages,
          _textMessage(messageId, role, name, ''),
        ],
      ),
    TextMessageContentEvent(:final messageId, :final delta) => _appendText(
      snapshot,
      messageId,
      TextMessageRole.assistant,
      delta,
    ),
    TextMessageChunkEvent(:final messageId, :final role, :final delta) =>
      _appendChunk(snapshot, messageId, role, delta ?? ''),
    ToolCallStartEvent(
      :final toolCallId,
      :final toolCallName,
      :final parentMessageId,
    ) =>
      _startToolCall(snapshot, toolCallId, toolCallName, parentMessageId),
    ToolCallArgsEvent(:final toolCallId, :final delta) => _appendToolArgs(
      snapshot,
      toolCallId,
      delta,
    ),
    ToolCallEndEvent(:final toolCallId) => _updateToolCall(
      snapshot,
      toolCallId,
      (view) => view.status == ToolCallStatus.inProgress
          ? _withStatus(view, ToolCallStatus.executing)
          : view,
    ),
    ToolCallChunkEvent() => _applyToolChunk(snapshot, event),
    ToolCallResultEvent(:final messageId, :final toolCallId, :final content) =>
      _completeToolCall(snapshot, messageId, toolCallId, content),
    StateSnapshotEvent(snapshot: final state) => snapshot.copyWith(
      state: state,
    ),
    StateDeltaEvent(:final delta) => _applyStateDelta(snapshot, delta),
    MessagesSnapshotEvent(:final messages) => snapshot.copyWith(
      messages: messages,
    ),
    _ => snapshot,
  };
}

/// A delta that doesn't apply (e.g. it was computed against a state this
/// client never saw) is dropped; the next snapshot resyncs the state.
AgentSnapshot _applyStateDelta(
  AgentSnapshot snapshot,
  List<Map<String, Object?>> delta,
) {
  try {
    return snapshot.copyWith(state: applyJsonPatch(snapshot.state, delta));
  } on FormatException {
    return snapshot;
  }
}

AgentSnapshot _startToolCall(
  AgentSnapshot snapshot,
  String toolCallId,
  String name,
  String? parentMessageId,
) {
  if (snapshot.toolCalls.any((view) => view.id == toolCallId)) return snapshot;
  final call = ToolCall(
    id: toolCallId,
    function: FunctionCall(name: name, arguments: ''),
  );
  final messages = snapshot.messages;
  final parentIndex = parentMessageId == null
      ? -1
      : messages.lastIndexWhere(
          (m) => m is AssistantMessage && m.id == parentMessageId,
        );
  final List<Message> nextMessages;
  if (parentIndex == -1) {
    nextMessages = [
      ...messages,
      AssistantMessage(id: parentMessageId ?? toolCallId, toolCalls: [call]),
    ];
  } else {
    final parent = messages[parentIndex] as AssistantMessage;
    nextMessages = [
      ...messages.sublist(0, parentIndex),
      parent.copyWith(toolCalls: [...?parent.toolCalls, call]),
      ...messages.sublist(parentIndex + 1),
    ];
  }
  return snapshot.copyWith(
    messages: nextMessages,
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

AgentSnapshot _appendToolArgs(
  AgentSnapshot snapshot,
  String toolCallId,
  String delta,
) {
  final call = snapshot.messages
      .whereType<AssistantMessage>()
      .expand((message) => message.toolCalls ?? const <ToolCall>[])
      .where((call) => call.id == toolCallId)
      .lastOrNull;
  if (call == null) return snapshot;
  final arguments = call.function.arguments + delta;
  final updatedCall = call.copyWith(
    function: call.function.copyWith(arguments: arguments),
  );
  final messages = [
    for (final message in snapshot.messages)
      if (message is AssistantMessage &&
          (message.toolCalls?.contains(call) ?? false))
        message.copyWith(
          toolCalls: [
            for (final c in message.toolCalls!)
              if (identical(c, call)) updatedCall else c,
          ],
        )
      else
        message,
  ];
  final args = parsePartialJson(arguments);
  return _updateToolCall(
    snapshot.copyWith(messages: messages),
    toolCallId,
    (view) => ToolCallView(
      id: view.id,
      name: view.name,
      status: view.status,
      args: args,
      result: view.result,
    ),
  );
}

AgentSnapshot _applyToolChunk(
  AgentSnapshot snapshot,
  ToolCallChunkEvent event,
) {
  final id = event.toolCallId ?? snapshot.toolCalls.lastOrNull?.id;
  if (id == null) return snapshot;
  var next = snapshot;
  if (!next.toolCalls.any((view) => view.id == id)) {
    final name = event.toolCallName;
    if (name == null) return snapshot;
    next = _startToolCall(next, id, name, event.parentMessageId);
  }
  final delta = event.delta;
  return delta == null ? next : _appendToolArgs(next, id, delta);
}

AgentSnapshot _completeToolCall(
  AgentSnapshot snapshot,
  String messageId,
  String toolCallId,
  String content,
) {
  if (snapshot.messages.any((m) => m is ToolMessage && m.id == messageId)) {
    return snapshot;
  }
  return _updateToolCall(
    snapshot.copyWith(
      messages: [
        ...snapshot.messages,
        ToolMessage(id: messageId, toolCallId: toolCallId, content: content),
      ],
    ),
    toolCallId,
    (view) => ToolCallView(
      id: view.id,
      name: view.name,
      status: ToolCallStatus.complete,
      args: view.args,
      result: content,
    ),
  );
}

/// Calls streamed as chunks have no End event; once the run finishes their
/// arguments are complete.
AgentSnapshot _finishToolArgs(AgentSnapshot snapshot) {
  if (!snapshot.toolCalls.any((v) => v.status == ToolCallStatus.inProgress)) {
    return snapshot;
  }
  return snapshot.copyWith(
    toolCalls: [
      for (final view in snapshot.toolCalls)
        if (view.status == ToolCallStatus.inProgress)
          _withStatus(view, ToolCallStatus.executing)
        else
          view,
    ],
  );
}

AgentSnapshot _updateToolCall(
  AgentSnapshot snapshot,
  String toolCallId,
  ToolCallView Function(ToolCallView view) update,
) {
  final index = snapshot.toolCalls.indexWhere((view) => view.id == toolCallId);
  if (index == -1) return snapshot;
  final view = snapshot.toolCalls[index];
  final updated = update(view);
  if (identical(updated, view)) return snapshot;
  return snapshot.copyWith(
    toolCalls: [
      ...snapshot.toolCalls.sublist(0, index),
      updated,
      ...snapshot.toolCalls.sublist(index + 1),
    ],
  );
}

ToolCallView _withStatus(ToolCallView view, ToolCallStatus status) {
  return ToolCallView(
    id: view.id,
    name: view.name,
    status: status,
    args: view.args,
    result: view.result,
  );
}

AgentSnapshot _appendChunk(
  AgentSnapshot snapshot,
  String? messageId,
  TextMessageRole? role,
  String delta,
) {
  final id = messageId ?? snapshot.messages.lastOrNull?.id;
  if (id == null) return snapshot;
  return _appendText(snapshot, id, role ?? TextMessageRole.assistant, delta);
}

/// Appends [delta] to message [messageId], creating it with [role] when it
/// doesn't exist yet.
AgentSnapshot _appendText(
  AgentSnapshot snapshot,
  String messageId,
  TextMessageRole role,
  String delta,
) {
  final messages = snapshot.messages;
  final index = messages.lastIndexWhere((m) => m.id == messageId);
  if (index == -1) {
    return snapshot.copyWith(
      messages: [...messages, _textMessage(messageId, role, null, delta)],
    );
  }
  final message = messages[index];
  return snapshot.copyWith(
    messages: [
      ...messages.sublist(0, index),
      _withText(message, '${message.content ?? ''}$delta'),
      ...messages.sublist(index + 1),
    ],
  );
}

Message _textMessage(
  String id,
  TextMessageRole role,
  String? name,
  String text,
) {
  return switch (role) {
    TextMessageRole.assistant => AssistantMessage(
      id: id,
      content: text,
      name: name,
    ),
    TextMessageRole.user => UserMessage(id: id, content: text, name: name),
    TextMessageRole.system => SystemMessage(id: id, content: text, name: name),
    TextMessageRole.developer => DeveloperMessage(
      id: id,
      content: text,
      name: name,
    ),
  };
}

/// Returns [message] with its text replaced by [text].
///
/// Only text messages are created by the reducer, so other message kinds
/// are returned unchanged.
Message _withText(Message message, String text) {
  return switch (message) {
    AssistantMessage() => message.copyWith(content: text),
    UserMessage(:final id, :final name) => UserMessage(
      id: id,
      content: text,
      name: name,
    ),
    SystemMessage(:final id, :final name) => SystemMessage(
      id: id,
      content: text,
      name: name,
    ),
    DeveloperMessage(:final id, :final name) => DeveloperMessage(
      id: id,
      content: text,
      name: name,
    ),
    _ => message,
  };
}
