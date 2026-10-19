part of 'copilot_chat_bloc.dart';

/// Events handled by [CopilotChatBloc].
sealed class CopilotChatEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// The user sent [text]; it is added as a user message and the agent runs.
///
/// Ignored when [text] is blank or the agent is already running.
final class const ChatMessageSent(
  /// What the user typed.
  final String text,
) extends CopilotChatEvent {
  /// Creates the event for sending [text].
  this;

  @override
  List<Object?> get props => [text];
}

/// The user asked to stop the current run.
final class const ChatStopRequested() extends CopilotChatEvent {
  /// Creates the event for stopping the run.
  this;
}

final class const _AgentStateChanged(final AgentState state)
    extends CopilotChatEvent;
