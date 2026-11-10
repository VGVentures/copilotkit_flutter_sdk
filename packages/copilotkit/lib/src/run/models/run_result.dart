/// How one run of an agent ended.
enum RunResult {
  /// The runtime finished the run without an error.
  finished,

  /// The run failed: the runtime reported an error, the transport failed or
  /// the connection closed early. The error is on the agent.
  failed,

  /// The turn was stopped or closed while the run was being sent or
  /// streamed.
  stopped,
}
