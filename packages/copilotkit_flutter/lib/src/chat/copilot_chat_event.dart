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
final class ChatMessageSent extends CopilotChatEvent {
  /// {@macro chat_message_sent}
  const new(this.text);

  /// What the user typed.
  final String text;

  @override
  List<Object?> get props => [text];
}

/// {@template chat_stop_requested}
/// The user asked to stop the current run.
/// {@endtemplate}
final class ChatStopRequested extends CopilotChatEvent {
  /// {@macro chat_stop_requested}
  const new();
}

final class _ChatSnapshotChanged extends CopilotChatEvent {
  const new(this.snapshot);

  final AgentSnapshot snapshot;
}
