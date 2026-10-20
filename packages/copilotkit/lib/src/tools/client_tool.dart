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

/// A tool the agent can call that is carried out in the app, with arguments
/// of type [T].
///
/// Register one with `CopilotKitClient.registerTool`. The client sends every
/// registered tool to the agent on each run, and when the agent calls one,
/// the tool decides who produces the result: a [FrontendTool] runs code, a
/// [HumanInTheLoopTool] waits for the user.
///
/// Sealed: switch over it to handle every kind of tool.
sealed class ClientTool<T> extends Equatable {
  const new({
    required this.name,
    required this.description,
    required this.parameters,
    required this.decode,
  });

  /// Unique tool name the agent calls the tool by.
  final String name;

  /// Tells the agent what the tool does and when to call it.
  final String description;

  /// Schema of the arguments the agent must send, built with [Ack.object].
  ///
  /// Sent to the agent as JSON Schema. Fields are required unless marked
  /// `.optional()`. The arguments of each call are validated with it before
  /// the tool runs; calls that don't match never run, and the agent gets a
  /// result listing the problems instead.
  final ObjectSchema parameters;

  /// Decodes the validated arguments, e.g. a model's `fromJson`. Use
  /// `JsonObject.new` to get them as a [JsonObject].
  final JsonDecoder<T> decode;
}

/// A tool the agent can call that runs in the app, with arguments of type
/// [T].
///
/// Register it with `CopilotKitClient.registerTool`. When the agent calls
/// it, the arguments are validated with `parameters`, decoded with `decode`
/// and passed to [handler]; its result is appended as a tool message, and
/// the agent continues in the same turn.
class const FrontendTool<T>({
  required super.name,
  required super.description,
  required super.parameters,
  required super.decode,

  /// Runs the tool when the agent calls it.
  required final FrontendToolHandler<T> handler,
}) extends ClientTool<T> {
  /// Creates a tool the agent can call.
  this;

  /// Decodes [args] and runs [handler] with them.
  ///
  /// Throws what `decode` or [handler] throw.
  Future<String> run(JsonObject args, {required CancellationSignal signal}) =>
      handler(args.decode(decode), signal: signal);

  @override
  List<Object?> get props => [name, description, parameters, decode, handler];
}

/// A tool whose result is the user's answer, not the result of code, with
/// arguments of type [T].
///
/// Register it with `CopilotKitClient.registerTool`, or with
/// `CopilotHumanInTheLoop` in Flutter. When the agent calls it, the call is
/// marked as awaiting a response (`ToolCallView.awaitingResponse`) and the
/// turn waits until the app answers with `CopilotKitClient.respondToToolCall`,
/// whenever the user decides. That answer is appended as the tool message,
/// and the agent continues in the same turn, unless [followUp] is `false`.
///
/// The agent stays running while it waits: `CopilotAgentState.isRunning` is
/// true for the whole turn. Stopping the agent, or unregistering the tool
/// while a call waits, answers the call as cancelled.
class const HumanInTheLoopTool<T>({
  required super.name,
  required super.description,
  required super.parameters,
  required super.decode,

  /// Whether the agent runs again with the user's answer once the call is
  /// answered. When `false`, the answer is recorded and the turn ends without
  /// another run, e.g. for a tool that only shows a notice.
  final bool followUp = true,
}) extends ClientTool<T> {
  /// Creates a tool the user answers.
  this;

  @override
  List<Object?> get props => [name, description, parameters, decode, followUp];
}
