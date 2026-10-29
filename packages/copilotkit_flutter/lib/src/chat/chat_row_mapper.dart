import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/models/chat_row.dart';

/// Maps an agent's messages and tool calls to the rows a chat UI shows.
class const ChatRowMapper() {
  /// Creates a mapper.
  this;

  /// The rows shown for [agentState], oldest first.
  ///
  /// User and assistant messages with text become [ChatMessageRow]s; each
  /// tool call on an assistant message follows it as a [ChatToolCallRow].
  /// Tool results, system, developer and unsupported messages are not shown.
  List<ChatRow> call(CopilotAgentState agentState) {
    final calls = {for (final call in agentState.toolCalls) call.id: call};
    return [
      for (final message in agentState.messages) ..._rowsFor(message, calls),
    ];
  }

  /// The rows shown for [message]: its text, then each of its tool calls
  /// found in [calls].
  List<ChatRow> _rowsFor(Message message, Map<String, ToolCallView> calls) => [
    if (_hasText(message)) ChatMessageRow(message),
    if (message is AssistantMessage)
      for (final toolCall in message.toolCalls)
        if (calls[toolCall.id] case final call?) ChatToolCallRow(call),
  ];

  bool _hasText(Message message) => switch (message) {
    UserMessage(:final content) => content.isNotEmpty,
    AssistantMessage(:final content) => (content ?? '').isNotEmpty,
    _ => false,
  };
}
