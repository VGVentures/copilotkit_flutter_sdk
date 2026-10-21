import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:equatable/equatable.dart';

/// A tool call made by the agent, shaped for rendering.
class const ToolCallView({
  /// The id of the tool call.
  ///
  /// It stays the same for the whole call, so use it as a widget key.
  required final String id,

  /// Name of the tool being called.
  required final String name,

  /// Where the call is in its lifecycle.
  required final ToolCallStatus status,

  /// Arguments sent by the agent, as a JSON object; partial while [status]
  /// is [ToolCallStatus.inProgress], so decode them with
  /// `ClientTool.tryDecode`. Unmodifiable when set by the SDK.
  final Map<String, Object?> args = const {},

  /// Result string; set once [status] is [ToolCallStatus.complete].
  final String? result,

  /// Whether the call waits for the user: the agent called a
  /// `HumanInTheLoopTool` and the app has yet to answer with
  /// `CopilotKitClient.respondToToolCall`. Only set while [status] is
  /// [ToolCallStatus.executing].
  final bool awaitingResponse = false,
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
    bool? awaitingResponse,
  }) {
    return ToolCallView(
      id: id,
      name: name,
      status: status ?? this.status,
      args: args ?? this.args,
      result: result == null ? this.result : result(),
      awaitingResponse: awaitingResponse ?? this.awaitingResponse,
    );
  }

  @override
  List<Object?> get props => [id, name, status, args, result, awaitingResponse];
}
