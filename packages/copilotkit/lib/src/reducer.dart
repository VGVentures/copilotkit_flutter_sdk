import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_snapshot.dart';

/// Applies [event] to [snapshot] and returns the resulting snapshot.
///
/// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
/// don't change the agent return [snapshot] itself, so callers can skip
/// emitting when `identical(previous, next)`.
AgentSnapshot reduceAgentEvent(AgentSnapshot snapshot, BaseEvent event) {
  return switch (event) {
    RunStartedEvent() => snapshot.copyWith(isRunning: true, error: null),
    RunFinishedEvent() => snapshot.copyWith(isRunning: false),
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
    _ => snapshot,
  };
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
