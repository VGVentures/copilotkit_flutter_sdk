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
  /// Creates the state of a chat.
  this;

  /// Builds the state shown for [agentState].
  ///
  /// User and assistant messages with text become [ChatMessageRow]s; each
  /// tool call on an assistant message follows it as a [ChatToolCallRow].
  /// Tool results, system and developer messages are not shown.
  factory fromAgentState(CopilotAgentState agentState) {
    final calls = {for (final call in agentState.toolCalls) call.id: call};
    return CopilotChatState(
      rows: [
        for (final message in agentState.messages) ..._rowsFor(message, calls),
      ],
      isRunning: agentState.isRunning,
      error: agentState.error,
    );
  }

  @override
  List<Object?> get props => [rows, isRunning, error];

  /// The rows shown for [message]: its text, then each of its tool calls
  /// found in [calls].
  static List<ChatRow> _rowsFor(
    Message message,
    Map<String, ToolCallView> calls,
  ) => [
    if (_hasText(message)) ChatMessageRow(message),
    if (message is AssistantMessage)
      for (final toolCall in message.toolCalls ?? const <ToolCall>[])
        if (calls[toolCall.id] case final call?) ChatToolCallRow(call),
  ];

  static bool _hasText(Message message) =>
      (message is UserMessage || message is AssistantMessage) &&
      (message.content ?? '').isNotEmpty;
}
