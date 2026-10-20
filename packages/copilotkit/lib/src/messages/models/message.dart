import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/messages/models/tool_call.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// A message of a conversation with an agent.
///
/// Sealed: switch over it to handle every kind of message. Messages the SDK
/// doesn't model, e.g. reasoning, are kept as an [UnsupportedMessage] so they
/// go back to the runtime unchanged.
sealed class Message extends Equatable {
  const new({required this.id});

  /// Creates the message that the AG-UI [message] describes.
  ///
  /// Lossless: a message that can't be modeled exactly, e.g. reasoning or a
  /// user message with images, becomes an [UnsupportedMessage] that holds its
  /// JSON, and [toAgUi] turns it back into the same AG-UI message. The only
  /// changes are a generated id for a message that has none, and an empty
  /// list of tool calls, which goes back as no list.
  @internal
  factory fromAgUi(ag_ui.Message message) {
    // AG-UI types the id as nullable; only reasoning messages may omit it on
    // the wire.
    final id = message.id ?? const Uuid().v4();
    return switch (message) {
      ag_ui.UserMessage(messageContent: ag_ui.TextContent(:final text)) =>
        UserMessage(
          id: id,
          content: text,
          name: message.name,
          encryptedValue: message.encryptedValue,
        ),
      ag_ui.AssistantMessage(:final toolCalls)
          when toolCalls?.every((call) => call.type == 'function') ?? true =>
        AssistantMessage(
          id: id,
          content: message.content,
          toolCalls: [...?toolCalls?.map(ToolCall.fromAgUi)],
          name: message.name,
          encryptedValue: message.encryptedValue,
        ),
      ag_ui.SystemMessage() => SystemMessage(
        id: id,
        content: message.content,
        name: message.name,
        encryptedValue: message.encryptedValue,
      ),
      ag_ui.DeveloperMessage() => DeveloperMessage(
        id: id,
        content: message.content,
        name: message.name,
        encryptedValue: message.encryptedValue,
      ),
      ag_ui.ToolMessage() => ToolMessage(
        id: id,
        content: message.content,
        toolCallId: message.toolCallId,
        error: message.error,
        encryptedValue: message.encryptedValue,
      ),
      _ => UnsupportedMessage(id: id, data: Map.unmodifiable(message.toJson())),
    };
  }

  /// Unique id of the message in its conversation.
  final String id;

  /// This message as an AG-UI message.
  @internal
  ag_ui.Message toAgUi();
}

/// A text message written by the user.
final class const UserMessage({
  required super.id,

  /// Text of the message.
  required final String content,

  /// Name of the author, if the runtime sets one.
  final String? name,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Message {
  /// Creates a message from the user with the text [content].
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.UserMessage(
    id: id,
    content: content,
    name: name,
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, content, name, encryptedValue];
}

/// A message from the assistant: text, tool calls or both.
final class const AssistantMessage({
  required super.id,

  /// Text of the message, if any.
  final String? content,

  /// Calls to tools the assistant made in this message, in order.
  final List<ToolCall> toolCalls = const [],

  /// Name of the author, if the runtime sets one.
  final String? name,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Message {
  /// Creates a message from the assistant.
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.AssistantMessage(
    id: id,
    content: content,
    toolCalls: toolCalls.isEmpty
        ? null
        : [for (final call in toolCalls) call.toAgUi()],
    name: name,
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, content, toolCalls, name, encryptedValue];
}

/// A system prompt: instructions for the agent.
final class const SystemMessage({
  required super.id,

  /// Text of the instructions.
  required final String content,

  /// Name of the author, if the runtime sets one.
  final String? name,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Message {
  /// Creates a system message with the text [content].
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.SystemMessage(
    id: id,
    content: content,
    name: name,
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, content, name, encryptedValue];
}

/// A developer prompt: instructions for the agent from the app's developer.
final class const DeveloperMessage({
  required super.id,

  /// Text of the instructions.
  required final String content,

  /// Name of the author, if the runtime sets one.
  final String? name,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Message {
  /// Creates a developer message with the text [content].
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.DeveloperMessage(
    id: id,
    content: content,
    name: name,
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, content, name, encryptedValue];
}

/// The result of the tool call [toolCallId].
final class const ToolMessage({
  required super.id,

  /// The result, as sent to the agent.
  required final String content,

  /// Id of the `ToolCall` this message answers.
  required final String toolCallId,

  /// Error reported for the call, if it failed.
  final String? error,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Message {
  /// Creates the result [content] of the tool call [toolCallId].
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.ToolMessage(
    id: id,
    content: content,
    toolCallId: toolCallId,
    error: error,
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, content, toolCallId, error, encryptedValue];
}

/// A message the SDK doesn't model, e.g. reasoning, activity or a user
/// message with images.
///
/// Kept so the conversation goes back to the runtime unchanged; chat UIs
/// usually skip it.
final class const UnsupportedMessage({
  required super.id,

  /// The message as the runtime sent it, as a JSON object. Don't change
  /// it: it is sent back as is.
  required final Map<String, Object?> data,
}) extends Message {
  /// Creates a message that holds the runtime's [data].
  this;

  @override
  @internal
  ag_ui.Message toAgUi() => ag_ui.Message.fromJson(data);

  @override
  List<Object?> get props => [id, data];
}
