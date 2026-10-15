part of 'copilot_chat_bloc.dart';

/// Events handled by [CopilotChatBloc].
sealed class CopilotChatEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// {@template chat_message_sent}
/// The user sent [text]; it is added as a user message and the agent runs.
///
/// Ignored when [text] is blank or the agent is already running.
/// {@endtemplate}
final class const ChatMessageSent(
  /// What the user typed.
  final String text,
) extends CopilotChatEvent {
  /// {@macro chat_message_sent}
  this;

  @override
  List<Object?> get props => [text];
}

/// {@template chat_stop_requested}
/// The user asked to stop the current run.
/// {@endtemplate}
final class const ChatStopRequested() extends CopilotChatEvent {
  /// {@macro chat_stop_requested}
  this;
}

final class const _ChatSnapshotChanged(final AgentState snapshot)
    extends CopilotChatEvent;
