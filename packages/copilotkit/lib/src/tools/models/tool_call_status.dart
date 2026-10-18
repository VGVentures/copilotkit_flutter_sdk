/// Lifecycle of a tool call as seen by the UI.
enum ToolCallStatus {
  /// The agent is still streaming the arguments; `ToolCallView.args` is
  /// partial.
  inProgress,

  /// The arguments are complete and the call is waiting for its result: a
  /// frontend handler is running, or the runtime is running a backend tool.
  executing,

  /// The call finished with a result; `ToolCallView.result` is set.
  complete,

  /// The call ended without a usable result: its handler threw, the arguments
  /// didn't match the schema, no tool handles it, or the run ended early.
  /// `ToolCallView.result` holds the message the agent got instead.
  failed,

  /// The call was cut short because the run was stopped.
  /// `ToolCallView.result` holds the message the agent got instead.
  cancelled;

  /// Whether the call has ended, successfully or not.
  bool get isFinished => switch (this) {
    inProgress || executing => false,
    complete || failed || cancelled => true,
  };
}
