/// @docImport 'package:copilotkit_flutter/src/tools/tools.dart';
library;

import 'package:copilotkit/copilotkit.dart';
import 'package:equatable/equatable.dart';

/// One row of a chat UI.
sealed class ChatRow extends Equatable {
  const new();
}

/// A user or assistant text [message].
final class const ChatMessageRow(
  /// The message to show: a [UserMessage] or an [AssistantMessage], whose
  /// `content` is the text.
  final Message message,
) extends ChatRow {
  /// Creates a row for a text [message].
  this;

  @override
  List<Object?> get props => [message];
}

/// A tool [call]; render it with [ToolCallWidget].
final class const ChatToolCallRow(
  /// The tool call to show.
  final ToolCallView call,
) extends ChatRow {
  /// Creates a row for a tool [call].
  this;

  @override
  List<Object?> get props => [call];
}
