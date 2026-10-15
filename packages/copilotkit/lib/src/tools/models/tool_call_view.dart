import 'package:copilotkit/src/tools/models/tool_call_status.dart';

/// A tool call made by the agent, shaped for rendering.
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
  /// Creates a view of a tool call.
  this;
}
