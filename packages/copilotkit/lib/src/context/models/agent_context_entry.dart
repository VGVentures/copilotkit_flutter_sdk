import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A piece of app data shared with the agent.
///
/// Add it with `CopilotKitClient.addContext`; every run sends all entries in
/// `CopilotKitClient.context` as `RunAgentInput.context`, with [value]
/// JSON-encoded. Keep the [id] to update or remove the entry later.
// The default id is generated, so the constructor can't be const.
// ignore: prefer_const_constructors_in_immutables
class AgentContextEntry({
  /// Tells the agent what [value] is.
  required final String description,

  /// The data shared with the agent, as a JSON object, e.g. a model's
  /// `toJson()`.
  required final Map<String, Object?> value,
  String? id,
}) extends Equatable {
  /// Creates an entry; a random [id] is generated when none is given.
  this;

  /// Identifies the entry in `CopilotKitClient.updateContext` and
  /// `CopilotKitClient.removeContext`.
  final String id = id ?? const Uuid().v4();

  /// Returns a copy with [value] replaced.
  AgentContextEntry copyWith({required Map<String, Object?> value}) =>
      AgentContextEntry(id: id, description: description, value: value);

  @override
  List<Object?> get props => [id, description, value];
}
