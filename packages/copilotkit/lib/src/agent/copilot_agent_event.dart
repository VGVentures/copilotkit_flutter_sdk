import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What can change a `CopilotAgent`.
///
/// Internal: the client adds these; apps drive the agent through `run()`,
/// `stop()` and `addMessage()` and observe it through `state` and `stream`.
@internal
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

/// The app appended [message] to the conversation.
@internal
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

/// The client ended the tool call [toolCallId] with [content] as its result
/// and [status] as its outcome, e.g. because its handler ran, threw or was
/// stopped.
@internal
final class const AgentToolCallClosed({
  /// Id of the tool call.
  required final String toolCallId,

  /// Id of the tool message that holds [content].
  required final String messageId,

  /// The result sent to the agent.
  required final String content,

  /// How the call ended; always finished.
  required final ToolCallStatus status,
}) extends CopilotAgentEvent {
  /// Creates the event for ending [toolCallId].
  this;

  @override
  List<Object?> get props => [toolCallId, messageId, content, status];
}
