import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/frontend_tool_handler.dart';
import 'package:equatable/equatable.dart';

/// A tool the agent can call that runs in the app.
///
/// Register it with `ToolRegistered`. When the agent calls it,
/// [handler] runs, its result is appended as a tool message, and the agent
/// continues in the same turn.
class const FrontendTool({
  /// Unique tool name the agent calls the tool by.
  required final String name,

  /// Tells the agent what the tool does and when to call it.
  required final String description,

  /// Schema of the arguments the agent must send, built with [Ack.object].
  ///
  /// Sent to the agent as JSON Schema. Fields are required unless marked
  /// `.optional()`. The arguments of each call are parsed with it before
  /// [handler] runs.
  required final ObjectSchema parameters,

  /// Runs the tool when the agent calls it.
  required final FrontendToolHandler handler,
}) extends Equatable {
  /// Creates a tool the agent can call.
  this;

  @override
  List<Object?> get props => [name, description, parameters, handler];
}
