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
/// the `onError` of `CopilotKitBloc`.
typedef FrontendToolHandler = Future<String> Function(
  Map<String, Object?> args, {
  required CancellationSignal signal,
});

/// A tool the agent can call that is carried out in the app.
///
/// Register one with `ToolRegistered`. The client sends every registered tool
/// to the agent on each run, and when the agent calls one, the tool decides
/// who produces the result: a [FrontendTool] runs code, a
/// [HumanInTheLoopTool] waits for the user.
///
/// Sealed: switch over it to handle every kind of tool.
sealed class ClientTool extends Equatable {
  const new({
    required this.name,
    required this.description,
    required this.parameters,
    this.agentId,
  });

  /// Unique tool name the agent calls the tool by.
  final String name;

  /// Tells the agent what the tool does and when to call it.
  final String description;

  /// Schema of the arguments the agent must send, built with [Ack.object].
  ///
  /// Sent to the agent as JSON Schema. Fields are required unless marked
  /// `.optional()`. The arguments of each call are parsed with it before the
  /// tool runs; calls that don't match never run, and the agent gets a result
  /// listing the problems instead.
  final ObjectSchema parameters;

  /// Id of the only agent that gets the tool, or `null` (the default) for
  /// every agent.
  ///
  /// A tool is registered by [name], so at most one tool with a given name
  /// exists at a time, whichever agent it is for.
  final String? agentId;

  /// Whether the agent [agentId] can call this tool.
  bool appliesTo(String agentId) =>
      this.agentId == null || this.agentId == agentId;

  @override
  List<Object?> get props => [name, description, parameters, agentId];
}

/// A tool the agent can call that runs in the app.
///
/// Register it with `ToolRegistered`. When the agent calls it,
/// [handler] runs, its result is appended as a tool message, and the agent
/// continues in the same turn.
class const FrontendTool({
  required super.name,
  required super.description,
  required super.parameters,

  /// Runs the tool when the agent calls it.
  required final FrontendToolHandler handler,
  super.agentId,
}) extends ClientTool {
  /// Creates a tool the agent can call.
  this;

  @override
  List<Object?> get props => [...super.props, handler];
}

/// A tool whose result is the user's answer, not the result of code.
///
/// Register it with `ToolRegistered`, or with `CopilotHumanInTheLoop` in
/// Flutter. When the agent calls it, the call is marked as awaiting a response
/// (`ToolCallView.awaitingResponse`) and the turn waits until the app adds a
/// `ToolCallResponded` for the call, whenever the user decides. That
/// response is appended as the tool message, and the agent continues in the
/// same turn, unless [followUp] is `false`.
///
/// The agent stays running while it waits: `CopilotAgentState.isRunning` is
/// true for the whole turn. Stopping the agent, or unregistering the tool
/// while a call waits, answers the call as cancelled.
class const HumanInTheLoopTool({
  required super.name,
  required super.description,
  required super.parameters,
  super.agentId,

  /// Whether the agent runs again with the user's answer once the call is
  /// answered. When `false`, the answer is recorded and the turn ends without
  /// another run, e.g. for a tool that only shows a notice.
  final bool followUp = true,
}) extends ClientTool {
  /// Creates a tool the user answers.
  this;

  @override
  List<Object?> get props => [...super.props, followUp];
}

/// A tool that only renders a component in the chat: the agent calls it with
/// the component's arguments and the app draws them.
///
/// Register it with `ToolRegistered`, or with `CopilotComponent` in Flutter,
/// which also draws the component. It has no handler and nothing waits for the
/// user, so the client does not run, await or follow up on a call to it: the
/// call renders from its arguments as they stream in, and the turn ends
/// without another run (unless the same turn has other calls that follow up).
///
/// The conversation stays valid for the next run: a call without a result
/// from the agent is closed by the client with a short note that the
/// component was displayed, so an agent that needs a tool message for every
/// tool call, such as the runtime's built-in one, gets one. A runtime that
/// answers frontend tool calls itself, e.g. with a placeholder result in the
/// event stream, completes the call earlier and the client adds nothing.
///
/// The description sent to the agent says that the tool renders a UI
/// component, followed by the `description` given here.
class const ComponentTool({
  required super.name,
  required super.parameters,

  /// What the component shows and when to use it, added to the sentence
  /// telling the agent that the tool displays the component.
  String? description,
  super.agentId,
}) extends ClientTool {
  /// Creates a tool that renders a component named [name].
  ///
  /// The description sent to the agent is a sentence saying that the tool
  /// displays the "[name]" component, followed by [description] when given.
  this
    : super(
        description:
            'Use this tool to display the "$name" component in the chat. '
            'This tool renders a visual UI component for the user.'
            '${description == null ? '' : '\n\n$description'}',
      );
}
