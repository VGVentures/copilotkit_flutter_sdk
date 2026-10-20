/// @docImport 'package:copilotkit/src/client/copilotkit_client.dart';
/// @docImport 'package:copilotkit/src/tools/client_tool.dart';
library;

import 'package:copilotkit/src/json/models/json_object.dart';
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
  /// [ToolCallStatus.inProgress], so decode them with
  /// [JsonObject.tryDecode].
  final JsonObject args = const JsonObject(),

  /// Result string; set once [status] is [ToolCallStatus.complete].
  final String? result,

  /// Whether the call waits for the user: the agent called a
  /// [HumanInTheLoopTool] and the app has yet to answer with
  /// [CopilotKitClient.respondToToolCall]. Only set while [status] is
  /// [ToolCallStatus.executing].
  final bool awaitingResponse = false,
}) extends Equatable {
  /// Creates a view of a tool call.
  this;

  /// Returns a copy with the given fields replaced.
  ///
  /// [result] is a callback so a caller can set it (`result: () => text`),
  /// clear it (`result: () => null`) or leave it alone by not passing it.
  ToolCallView copyWith({
    ToolCallStatus? status,
    JsonObject? args,
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
