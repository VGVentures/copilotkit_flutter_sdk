import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';

/// Applies AG-UI text message events to a [CopilotKitAgentState].
///
/// Pure: [CopilotKitAgentState]s are never mutated, and events that don't
/// change the agent return the given snapshot itself.
class const TextMessageMapper() {
  /// Creates a text message mapper.
  this;

  /// Returns [snapshot] with an empty message [messageId] from [role]
  /// appended.
  CopilotKitAgentState start(
    CopilotKitAgentState snapshot,
    String messageId,
    TextMessageRole role,
    String? name,
  ) => snapshot.copyWith(
    messages: [
      ...snapshot.messages,
      role.message(messageId, name: name, text: ''),
    ],
  );

  /// Appends [delta] to message [messageId], creating it with [role] when it
  /// doesn't exist yet.
  CopilotKitAgentState append(
    CopilotKitAgentState snapshot,
    String messageId,
    TextMessageRole role,
    String delta,
  ) {
    final messages = snapshot.messages;
    final index = messages.lastIndexWhere((m) => m.id == messageId);
    if (index == -1) {
      return snapshot.copyWith(
        messages: [
          ...messages,
          role.message(messageId, text: delta),
        ],
      );
    }
    final message = messages[index];
    return snapshot.copyWith(
      messages: [...messages]
        ..[index] = message.withText('${message.content ?? ''}$delta'),
    );
  }

  /// Appends a chunk's [delta] to message [messageId].
  ///
  /// A chunk without [messageId] continues the last message, but only when it
  /// has the chunk's role, so assistant text never lands in a user message.
  CopilotKitAgentState appendChunk(
    CopilotKitAgentState snapshot,
    String? messageId,
    TextMessageRole? role,
    String delta,
  ) {
    final chunkRole = role ?? TextMessageRole.assistant;
    final last = snapshot.messages.lastOrNull;
    final id =
        messageId ??
        (last != null && last.textRole == chunkRole ? last.id : null);
    if (id == null) return snapshot;
    return append(snapshot, id, chunkRole, delta);
  }
}

extension on TextMessageRole {
  /// A message [id] from this role holding [text].
  Message message(String id, {required String text, String? name}) {
    return switch (this) {
      TextMessageRole.assistant => AssistantMessage(
        id: id,
        content: text,
        name: name,
      ),
      TextMessageRole.user => UserMessage(id: id, content: text, name: name),
      TextMessageRole.system => SystemMessage(
        id: id,
        content: text,
        name: name,
      ),
      TextMessageRole.developer => DeveloperMessage(
        id: id,
        content: text,
        name: name,
      ),
    };
  }
}

extension on Message {
  /// The role of this text message, or `null` for other message kinds.
  TextMessageRole? get textRole => switch (this) {
    AssistantMessage() => TextMessageRole.assistant,
    UserMessage() => TextMessageRole.user,
    SystemMessage() => TextMessageRole.system,
    DeveloperMessage() => TextMessageRole.developer,
    _ => null,
  };

  /// This message with its text replaced by [text].
  ///
  /// Only text messages are created by the mapper, so other message kinds
  /// are returned unchanged.
  Message withText(String text) {
    return switch (this) {
      final AssistantMessage message => message.copyWith(content: text),
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
      _ => this,
    };
  }
}
