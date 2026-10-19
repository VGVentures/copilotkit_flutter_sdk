/// Results sent to the agent for tool calls that never ran to completion.
enum FallbackToolResult {
  /// A tool call cut short by a stop.
  cancelled('Tool call cancelled.'),

  /// A tool call left open by a failed run.
  failed('Tool call failed: the run ended early.'),

  /// A call to a tool that isn't registered, e.g. because its `CopilotTool`
  /// was unmounted. Backend tool calls never get it: the runtime sends their
  /// results within the run.
  unavailable('Tool is not available.'),

  /// A handler threw. The error itself goes to `onError` only, so exception
  /// details never reach the model.
  handlerError('Tool failed.');

  new(this.message);

  /// The result text sent to the agent.
  final String message;
}
