part of 'copilot_chat_bloc.dart';

/// What a chat UI shows: ordered [rows], whether the agent [isRunning] and
/// the [error] that ended the last run.
final class const CopilotChatState({
  /// Rows to render, oldest first.
  final List<ChatRow> rows = const [],

  /// Whether the agent is running; show stop instead of send.
  final bool isRunning = false,

  /// Error that ended the last run, or `null`.
  final Object? error,
}) extends Equatable {
  /// Creates the state a chat UI shows.
  this;

  /// Builds the state shown for [snapshot].
  ///
  /// User and assistant messages with text become [ChatMessageRow]s; each
  /// tool call on an assistant message follows it as a [ChatToolCallRow].
  /// Tool results, system and developer messages are not shown.
  factory fromSnapshot(AgentSnapshot snapshot) {
    final calls = {for (final call in snapshot.toolCalls) call.id: call};
    return CopilotChatState(
      rows: [
        for (final message in snapshot.messages) ..._rowsFor(message, calls),
      ],
      isRunning: snapshot.isRunning,
      error: snapshot.error,
    );
  }

  @override
  List<Object?> get props => [rows, isRunning, error];
}

/// The rows shown for [message]: its text, then each of its tool calls found
/// in [calls].
List<ChatRow> _rowsFor(Message message, Map<String, ToolCallView> calls) => [
  if (_hasText(message)) ChatMessageRow(message),
  if (message is AssistantMessage)
    for (final toolCall in message.toolCalls ?? const <ToolCall>[])
      if (calls[toolCall.id] case final call?) ChatToolCallRow(call),
];

bool _hasText(Message message) =>
    (message is UserMessage || message is AssistantMessage) &&
    (message.content ?? '').isNotEmpty;

/// One row of a chat UI.
sealed class ChatRow extends Equatable {
  const new();
}

/// A user or assistant text [message].
final class const ChatMessageRow(
  /// The message to show; its `content` is the text.
  final Message message,
) extends ChatRow {
  /// Creates a row for a text [message].
  this;

  @override
  List<Object?> get props => [message];
}

/// A tool [call]; render it with `ToolCallWidget`.
final class const ChatToolCallRow(
  /// The tool call to show.
  final ToolCallView call,
) extends ChatRow {
  /// Creates a row for a tool [call].
  this;

  @override
  List<Object?> get props => [call];
}
