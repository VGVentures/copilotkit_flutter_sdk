import 'dart:async';

import 'package:ack/ack.dart';

/// Handles a frontend tool call on the device.
///
/// Receives the decoded tool [args] and a [signal] that is cancelled when the
/// run is stopped. Returns the result string sent back to the agent. If it
/// throws, the agent gets a generic failure result and the error goes to
/// `CopilotKitClient.onError`.
typedef FrontendToolHandler = Future<String> Function(
  Map<String, Object?> args, {
  required CancellationSignal signal,
});

/// {@template frontend_tool}
/// A tool the agent can call that runs in the app.
///
/// Register it with `CopilotKitClient.registerTool`. When the agent calls it,
/// [handler] runs, its result is appended as a tool message, and the agent
/// continues in the same turn.
/// {@endtemplate}
class const FrontendTool({
  /// Unique tool name the agent calls the tool by.
  required final String name,

  /// Tells the agent what the tool does and when to call it.
  required final String description,

  /// Schema of the arguments the agent must send, built with [Ack.object].
  ///
  /// Sent to the agent as JSON Schema. Fields are required unless marked
  /// `.optional()`.
  required final ObjectSchema parameters,

  /// Runs the tool when the agent calls it.
  required final FrontendToolHandler handler,
}) {
  /// {@macro frontend_tool}
  this;
}

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

/// {@template tool_call_view}
/// A tool call made by the agent, shaped for rendering.
/// {@endtemplate}
class const ToolCallView({
  /// Tool call id; stable for the whole call, use it as a widget key.
  required final String id,

  /// Name of the tool being called.
  required final String name,

  /// Where the call is in its lifecycle.
  required final ToolCallStatus status,

  /// Arguments sent by the agent; partial while [status] is
  /// [ToolCallStatus.inProgress].
  final Map<String, Object?> args = const {},

  /// Result string; set once [status] is [ToolCallStatus.complete].
  final String? result,
}) {
  /// {@macro tool_call_view}
  this;
}

/// {@template cancellation_signal}
/// Tells a tool handler that its run was stopped.
///
/// The client creates one per tool call and cancels it when the run stops.
/// Handlers check [isCancelled] or await [whenCancelled] to stop early.
/// {@endtemplate}
class CancellationSignal() {
  /// {@macro cancellation_signal}
  this;

  final _cancelled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the signal. Calling it again has no effect.
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
