part of 'copilot_agent_bloc.dart';

/// What can change a [CopilotAgentBloc].
///
/// Apps add [AgentMessageAdded], [AgentMessagesSet], [AgentStateSet] and
/// [AgentStatePatched] to edit the conversation and the shared state; the
/// other events are internal and added by the `CopilotKitBloc` that runs the
/// agent. Runs and stops are requested from the `CopilotKitBloc` with
/// `AgentRunRequested` and `AgentStopRequested`.
///
/// The agent applies events in the order they were added, and a run reads the
/// agent only after every event added before it has been applied. So adding
/// an edit and then requesting a run in the same tick sends the edit with
/// that run.
sealed class CopilotAgentEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => const [];
}

/// An AG-UI [event] to apply, from the runtime or produced locally (a tool
/// result).
@internal
final class const AgentEventReceived(final BaseEvent event)
    extends CopilotAgentEvent {
  /// Creates the event for applying [event].
  this;

  @override
  List<Object?> get props => [event];
}

/// The app appended [message] to the conversation, without starting a run.
final class const AgentMessageAdded(final Message message)
    extends CopilotAgentEvent {
  /// Creates the event for appending [message].
  this;

  @override
  List<Object?> get props => [message];
}

/// The app replaced every message of the conversation with [messages].
///
/// Use it to reset a conversation (`AgentMessagesSet([])`) or to restore a
/// saved one. Tool calls that no message refers to anymore are dropped from
/// `CopilotAgentState.toolCalls`. Allowed while the agent is running; the
/// events that stream in afterwards apply on top of [messages].
final class const AgentMessagesSet(final List<Message> messages)
    extends CopilotAgentEvent {
  /// Creates the event for replacing the conversation with [messages].
  this;

  @override
  List<Object?> get props => [messages];
}

/// The app replaced the shared state with [state].
///
/// The next run sends [state] as `RunAgentInput.state`. [state] is treated
/// as immutable: pass a new value for every change instead of mutating one
/// you already passed. A `STATE_SNAPSHOT` from the runtime replaces it again,
/// and a `STATE_DELTA` patches it, so a local edit made during a run can be
/// overwritten by the agent.
final class const AgentStateSet(final Object? state) extends CopilotAgentEvent {
  /// Creates the event for replacing the shared state with [state].
  this;

  @override
  List<Object?> get props => [state];
}

/// The app edited the shared state with the RFC 6902 JSON Patch
/// [operations], the same format as a `STATE_DELTA`.
///
/// A state of `null` is patched as an empty object. When an operation
/// doesn't apply (a missing path, a failed `test`), none of them does: the
/// state stays as it was and the error goes to `BlocObserver.onError`.
final class const AgentStatePatched(final List<Map<String, Object?>> operations)
    extends CopilotAgentEvent {
  /// Creates the event for patching the shared state with [operations].
  this;

  @override
  List<Object?> get props => [operations];
}

/// A turn started: the agent is running until [AgentTurnEnded].
@internal
final class const AgentTurnStarted() extends CopilotAgentEvent {
  /// Creates the event for a turn starting.
  this;
}

/// The turn ended, whether it finished, failed or was stopped.
@internal
final class const AgentTurnEnded() extends CopilotAgentEvent {
  /// Creates the event for a turn ending.
  this;
}

/// A run failed outside the event stream with [error] (transport, headers
/// or an early close).
@internal
final class const AgentRunFailed(final Object error) extends CopilotAgentEvent {
  /// Creates the event for a run failing with [error].
  this;

  @override
  List<Object?> get props => [error];
}

/// Asks the agent to complete [completer] once every event added before
/// this one has been applied.
///
/// Bloc delivers events asynchronously; the client adds this before it reads
/// the agent's state after adding events.
@internal
final class const AgentSettleRequested(final Completer<void> completer)
    extends CopilotAgentEvent {
  /// Creates the event for completing [completer].
  this;

  @override
  List<Object?> get props => [completer];
}
