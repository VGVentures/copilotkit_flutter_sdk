/// Lifecycle of a tool call as seen by the UI.
enum ToolCallStatus {
  /// The agent is still streaming the arguments; `ToolCallView.args` is
  /// partial.
  inProgress,

  /// The arguments are complete and the call has no result yet: a handler is
  /// running or the user is answering (`ToolCallView.awaitingResponse`).
  executing,

  /// The call has its result; `ToolCallView.result` is set.
  complete,
}
