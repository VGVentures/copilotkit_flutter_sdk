part of 'copilot_agent_bloc.dart';

/// What can change a [CopilotAgentBloc].
///
/// Apps add [AgentMessageAdded]; the other events are internal and added by
/// the `CopilotKitBloc` that runs the agent. Runs and stops are requested
/// from the `CopilotKitBloc` with `AgentRunRequested` and
/// `AgentStopRequested`.
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
