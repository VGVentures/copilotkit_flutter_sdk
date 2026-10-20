part of 'copilot_chat_bloc.dart';

/// What a chat UI shows: ordered [rows], whether the agent [isRunning] and
/// the [error] that ended the last run.
final class const CopilotChatState({
  /// Rows to render, oldest first.
  final List<ChatRow> rows = const [],

  /// Whether the agent is running; show stop instead of send.
  final bool isRunning = false,

  /// Error that ended the last run, or `null`.
  final Object? error,
}) extends Equatable {
  /// Creates the state of a chat.
  this;

  /// Builds the state shown for [agentState], with its rows mapped by
  /// [rows].
  factory fromAgentState(
    CopilotAgentState agentState, {
    ChatRowMapper rows = const ChatRowMapper(),
  }) => CopilotChatState(
    rows: rows.rowsFor(agentState),
    isRunning: agentState.isRunning,
    error: agentState.error,
  );

  @override
  List<Object?> get props => [rows, isRunning, error];
}
