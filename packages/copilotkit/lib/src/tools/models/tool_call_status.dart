/// Lifecycle of a tool call as seen by the UI.
enum ToolCallStatus {
  /// The agent is still streaming the arguments; `ToolCallView.args` is
  /// partial.
  inProgress,

  /// The arguments are complete and the handler is running.
  executing,

  /// The handler finished; `ToolCallView.result` is set.
  complete,
}
