part of 'copilot_kit_bloc.dart';

/// What an app can ask a [CopilotKitBloc] to do.
///
/// The outcome of every event is visible in [CopilotKitBloc.state], or in
/// the agent's state for runs and stops.
sealed class CopilotKitEvent extends Equatable {
  const new();
}

/// Opens the agent [agentId], making it available in
/// `CopilotKitState.agents`. Does nothing if it is already open.
final class const AgentOpened(final String agentId) extends CopilotKitEvent {
  /// Creates the event for opening [agentId].
  this;

  @override
  List<Object?> get props => [agentId];
}

/// Makes [tool] available to the agent on every run, or only to the runs of
/// `ClientTool.agentId` when it has one.
///
/// A tool with the same name replaces the previous one.
final class const ToolRegistered(final ClientTool tool)
    extends CopilotKitEvent {
  /// Creates the event for registering [tool].
  this;

  @override
  List<Object?> get props => [tool];
}

/// Unregisters [tool]. Does nothing once [tool] was replaced by another
/// registration under the same name.
///
/// A running turn that waits for the user to answer a call of a
/// `HumanInTheLoopTool` answers it as cancelled: with the tool gone, nothing
/// can answer it anymore. To swap a tool for an updated one, add
/// [ToolRegistered] for the new tool first (it replaces the old one), then
/// [ToolUnregistered] for the old one, which then does nothing, so no call is
/// cancelled. A tool equal to the registered one changes nothing, and the
/// registered instance stays.
final class const ToolUnregistered(final ClientTool tool)
    extends CopilotKitEvent {
  /// Creates the event for unregistering [tool].
  this;

  @override
  List<Object?> get props => [tool];
}

/// Shares [entry] with its agents on every run.
///
/// A `String` value is sent as it is and any other value is JSON-encoded on
/// every run; a run with a value that can't be encoded fails through the
/// client's `onError`. Entries with `AgentContextEntry.agentIds` only go to
/// the runs of those agents.
final class const ContextAdded(final AgentContextEntry entry)
    extends CopilotKitEvent {
  /// Creates the event for adding [entry].
  this;

  @override
  List<Object?> get props => [entry];
}

/// The user answered the call [toolCallId] of a `HumanInTheLoopTool` with
/// [result].
///
/// A `String` [result] is sent to the agent as it is; any other value is
/// JSON-encoded, and a value that can't be encoded is reported through the
/// client's `onError` and leaves the call waiting. The run that is waiting
/// for the call continues with it as the tool result.
///
/// Add it whenever the user decides. An answer that arrives before the client
/// starts waiting for the call (its arguments are complete but its run has not
/// finished streaming) is kept until it does. The event is ignored when the
/// call is unknown, belongs to no running turn, already has a result or was
/// answered already, or when its tool is not a registered `HumanInTheLoopTool`.
final class const ToolCallResponded(
  final String toolCallId,
  final Object? result,
) extends CopilotKitEvent {
  /// Creates the event for answering [toolCallId] with [result].
  this;

  @override
  List<Object?> get props => [toolCallId, result];
}

/// Replaces the value of the entry [id]; the next run sends [value], encoded
/// as described in [ContextAdded].
final class const ContextUpdated(final String id, final Object? value)
    extends CopilotKitEvent {
  /// Creates the event for updating the entry [id].
  this;

  @override
  List<Object?> get props => [id, value];
}

/// Removes the entry [id]; later runs no longer send it.
final class const ContextRemoved(final String id) extends CopilotKitEvent {
  /// Creates the event for removing the entry [id].
  this;

  @override
  List<Object?> get props => [id];
}

/// Runs the open agent [agentId] with all registered tools and context.
///
/// When [message] is given, it is appended to the conversation before the
/// run, and dropped with the run when the agent is already running.
///
/// When the agent calls registered frontend tools, their handlers run and
/// the agent runs again with the results, until it stops calling them. When
/// it calls a `HumanInTheLoopTool`, the turn waits for the user's
/// `ToolCallResponded` (or a stop) and then continues the same way, unless
/// that tool sets `followUp` to `false`. The agent's `isRunning` is true for
/// that whole turn. Errors go to
/// the client's `onError`. Tool calls that will never get a result (the
/// run failed, or no registered tool handles them) are closed with a result
/// saying so, so the next run sends a valid conversation. Does nothing if
/// the agent is not open or already running.
final class const AgentRunRequested(
  final String agentId, {

  /// Message to append before the run, e.g. what the user typed.
  final Message? message,
}) extends CopilotKitEvent {
  /// Creates the event for running [agentId].
  this;

  @override
  List<Object?> get props => [agentId, message];
}

/// Stops the current run of the agent [agentId], closing its connection.
///
/// The partial reply is kept and no further events are applied. Running
/// tool handlers get their signal cancelled, and any tool call without a
/// result is closed as cancelled so the conversation stays valid. If a
/// stream was open, the runtime is also asked to stop the run; if that
/// fails the error goes to the client's `onError`. Does nothing if the
/// agent is not running.
final class const AgentStopRequested(final String agentId)
    extends CopilotKitEvent {
  /// Creates the event for stopping [agentId].
  this;

  @override
  List<Object?> get props => [agentId];
}
