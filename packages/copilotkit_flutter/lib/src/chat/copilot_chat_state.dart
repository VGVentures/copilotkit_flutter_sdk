part of 'copilot_chat_bloc.dart';

/// {@template copilot_chat_state}
/// What a chat UI shows: ordered [rows], whether the agent [isRunning] and
/// the [error] that ended the last run.
/// {@endtemplate}
final class CopilotChatState extends Equatable {
  /// {@macro copilot_chat_state}
  const new({this.rows = const [], this.isRunning = false, this.error});

  /// Builds the state shown for [snapshot].
  ///
  /// User and assistant messages with text become [ChatMessageRow]s; each
  /// tool call on an assistant message follows it as a [ChatToolCallRow].
  /// Tool results, system and developer messages are not shown.
  factory fromSnapshot(AgentSnapshot snapshot) {
    final calls = {for (final call in snapshot.toolCalls) call.id: call};
    return CopilotChatState(
      rows: [
        for (final message in snapshot.messages) ...[
          if ((message is UserMessage || message is AssistantMessage) &&
              (message.content ?? '').isNotEmpty)
            ChatMessageRow(message),
          if (message is AssistantMessage)
            for (final toolCall in message.toolCalls ?? const <ToolCall>[])
              if (calls[toolCall.id] case final call?) ChatToolCallRow(call),
        ],
      ],
      isRunning: snapshot.isRunning,
      error: snapshot.error,
    );
  }

  /// Rows to render, oldest first.
  final List<ChatRow> rows;

  /// Whether the agent is running; show stop instead of send.
  final bool isRunning;

  /// Error that ended the last run, or `null`.
  final Object? error;

  @override
  List<Object?> get props => [rows, isRunning, error];
}

/// One row of a chat UI.
sealed class ChatRow extends Equatable {
  const new();
}

/// {@template chat_message_row}
/// A user or assistant text [message].
/// {@endtemplate}
final class ChatMessageRow extends ChatRow {
  /// {@macro chat_message_row}
  const new(this.message);

  /// The message to show; its `content` is the text.
  final Message message;

  @override
  List<Object?> get props => [message];
}

/// {@template chat_tool_call_row}
/// A tool [call]; render it with `ToolCallWidget`.
/// {@endtemplate}
final class ChatToolCallRow extends ChatRow {
  /// {@macro chat_tool_call_row}
  const new(this.call);

  /// The tool call to show.
  final ToolCallView call;

  @override
  List<Object?> get props => [call];
}
