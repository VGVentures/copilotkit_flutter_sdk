/// @docImport 'package:ag_ui/ag_ui.dart';
/// @docImport 'package:copilotkit/src/client/copilotkit_client.dart';
library;

import 'package:copilotkit/src/json/models/json_encodable.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A piece of app data shared with the agent.
///
/// Add it with [CopilotKitClient.addContext]; every run sends all entries in
/// [CopilotKitClient.context] as [RunAgentInput.context], with [value]
/// JSON-encoded. Keep the [id] to update or remove the entry later.
// The default id is generated, so the constructor can't be const.
// ignore: prefer_const_constructors_in_immutables
class AgentContextEntry({
  /// What [value] is, as told to the agent.
  required final String description,

  /// The data shared with the agent: an app model with `toJson`.
  required final JsonEncodable value,
  String? id,
}) extends Equatable {
  /// Creates an entry; a random [id] is generated when none is given.
  this;

  /// The id of the entry in [CopilotKitClient.updateContext] and
  /// [CopilotKitClient.removeContext].
  final String id = id ?? const Uuid().v4();

  /// Returns a copy with [value] replaced.
  AgentContextEntry copyWith({required JsonEncodable value}) =>
      AgentContextEntry(id: id, description: description, value: value);

  @override
  List<Object?> get props => [id, description, value];
}
