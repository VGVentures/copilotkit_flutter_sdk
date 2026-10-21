import 'package:copilotkit/src/messages/messages.dart';

/// The text of [message], or `null` for a message without text.
String? textOf(Message? message) => switch (message) {
  UserMessage(:final content) => content,
  AssistantMessage(:final content) => content,
  SystemMessage(:final content) => content,
  DeveloperMessage(:final content) => content,
  ToolMessage(:final content) => content,
  UnsupportedMessage() || null => null,
};
