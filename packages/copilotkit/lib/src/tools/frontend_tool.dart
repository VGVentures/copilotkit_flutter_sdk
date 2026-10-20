import 'package:ack/ack.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:equatable/equatable.dart';

/// Handles a frontend tool call on the device.
///
/// Receives the tool [args], validated by `FrontendTool.parameters` and
/// decoded by `FrontendTool.decode`, and a [signal] that is cancelled when
/// the run is stopped. Calls whose arguments don't match the schema never
/// reach the handler; the agent gets a result listing the problems instead.
///
/// Returns the result string sent back to the agent. If it throws, the agent
/// gets a generic failure result and the error goes to
/// the `onError` of `CopilotKitClient`.
typedef FrontendToolHandler<T> = Future<String> Function(
  T args, {
  required CancellationSignal signal,
});

/// A tool the agent can call that runs in the app, with arguments of type
/// [T].
///
/// Register it with `CopilotKitClient.registerTool`. When the agent calls
/// it, the arguments are validated with [parameters], decoded with [decode]
/// and passed to [handler]; its result is appended as a tool message, and
/// the agent continues in the same turn. Use `decode: JsonObject.new` to
/// get the arguments as a [JsonObject].
class const FrontendTool<T>({
  /// Unique tool name the agent calls the tool by.
  required final String name,

  /// Tells the agent what the tool does and when to call it.
  required final String description,

  /// Schema of the arguments the agent must send, built with [Ack.object].
  ///
  /// Sent to the agent as JSON Schema. Fields are required unless marked
  /// `.optional()`. The arguments of each call are validated with it before
  /// [decode] runs.
  required final ObjectSchema parameters,

  /// Decodes the validated arguments, e.g. a model's `fromJson`.
  required final JsonDecoder<T> decode,

  /// Runs the tool when the agent calls it.
  required final FrontendToolHandler<T> handler,
}) extends Equatable {
  /// Creates a tool the agent can call.
  this;

  /// Decodes [args] and runs [handler] with them.
  ///
  /// Throws what [decode] or [handler] throw.
  Future<String> run(JsonObject args, {required CancellationSignal signal}) =>
      handler(args.decode(decode), signal: signal);

  @override
  List<Object?> get props => [name, description, parameters, decode, handler];
}
