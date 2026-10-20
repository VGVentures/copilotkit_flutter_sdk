import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:equatable/equatable.dart';
import 'package:mocktail/mocktail.dart';

/// A call made on a [RecordingClient]: the method name and its arguments.
class const ClientCall(
  /// The name of the method called, e.g. `registerTool`.
  final String method,

  /// The arguments passed, in order.
  final List<Object?> arguments,
) extends Equatable {
  /// Creates a record of a call to [method] with [arguments].
  this;

  @override
  List<Object?> get props => [method, arguments];
}

/// A [CopilotKitClient] that records the tool and context calls made on it,
/// in order.
class RecordingClient extends Fake implements CopilotKitClient {
  /// The calls made so far.
  final List<ClientCall> calls = [];

  @override
  void registerTool(ClientTool<Object?> tool) =>
      calls.add(ClientCall('registerTool', [tool]));

  @override
  void unregisterTool(ClientTool<Object?> tool) =>
      calls.add(ClientCall('unregisterTool', [tool]));

  @override
  void respondToToolCall(String toolCallId, Object? result) =>
      calls.add(ClientCall('respondToToolCall', [toolCallId, result]));

  @override
  void addContext(AgentContextEntry entry) =>
      calls.add(ClientCall('addContext', [entry]));

  @override
  void updateContext(String id, Object? value) =>
      calls.add(ClientCall('updateContext', [id, value]));

  @override
  void removeContext(String id) => calls.add(ClientCall('removeContext', [id]));

  /// The entries passed to [addContext], in order.
  List<AgentContextEntry> get addedEntries => [
    for (final ClientCall(:method, :arguments) in calls)
      if (method == 'addContext') arguments.single! as AgentContextEntry,
  ];
}
