import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:equatable/equatable.dart';

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

  /// Result string; set once the call has finished (see
  /// [ToolCallStatus.isFinished]). For a failed or cancelled call, the message
  /// the agent got instead of a result.
  final String? result,
}) extends Equatable {
  /// Creates a view of a tool call.
  this;

  /// Returns a copy with the given fields replaced.
  ///
  /// [result] is a getter so a caller can set it (`result: () => text`),
  /// clear it (`result: () => null`) or leave it alone by not passing it.
  ToolCallView copyWith({
    ToolCallStatus? status,
    Map<String, Object?>? args,
    String? Function()? result,
  }) {
    return ToolCallView(
      id: id,
      name: name,
      status: status ?? this.status,
      args: args ?? this.args,
      result: result == null ? this.result : result(),
    );
  }

  @override
  List<Object?> get props => [id, name, status, args, result];
}
