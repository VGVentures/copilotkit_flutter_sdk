import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// A call the agent made to a tool, held by an `AssistantMessage`.
class const ToolCall({
  /// Tool call id; stable for the whole call.
  required final String id,

  /// Name of the tool being called.
  required final String name,

  /// Arguments as the raw JSON text streamed so far; partial while the call
  /// is still streaming in.
  required final String arguments,

  /// Opaque payload from the runtime, sent back to it unchanged.
  final String? encryptedValue,
}) extends Equatable {
  /// Creates a call to the tool [name].
  this;

  /// Creates the call that the AG-UI [call] describes; its function becomes
  /// [name] and [arguments].
  @internal
  factory fromAgUi(ag_ui.ToolCall call) => ToolCall(
    id: call.id,
    name: call.function.name,
    arguments: call.function.arguments,
    encryptedValue: call.encryptedValue,
  );

  /// Returns a copy with [arguments] replaced.
  ToolCall copyWith({String? arguments}) => ToolCall(
    id: id,
    name: name,
    arguments: arguments ?? this.arguments,
    encryptedValue: encryptedValue,
  );

  /// This call as an AG-UI function call.
  @internal
  ag_ui.ToolCall toAgUi() => ag_ui.ToolCall(
    id: id,
    function: ag_ui.FunctionCall(name: name, arguments: arguments),
    encryptedValue: encryptedValue,
  );

  @override
  List<Object?> get props => [id, name, arguments, encryptedValue];
}
