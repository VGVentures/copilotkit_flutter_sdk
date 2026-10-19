import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:equatable/equatable.dart';

/// Handles a frontend tool call on the device.
///
/// Receives the tool [args], already parsed by `FrontendTool.parameters`,
/// and a [signal] that is cancelled when the run is stopped. Calls whose
/// arguments don't match the schema never reach the handler; the agent gets a
/// result listing the problems instead.
///
/// Returns the result string sent back to the agent. If it throws, the agent
/// gets a generic failure result and the error goes to
/// the `onError` of `CopilotKitClient`.
typedef FrontendToolHandler = Future<String> Function(
  Map<String, Object?> args, {
  required CancellationSignal signal,
});

/// A tool the agent can call that runs in the app.
///
/// Register it with `CopilotKitClient.registerTool`. When the agent calls it,
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
