import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A piece of app data shared with the agent.
///
/// Add it with `ContextAdded`; every run sends the entries in
/// `CopilotKitState.context` that apply to its agent as
/// `RunAgentInput.context`. A [value] that is a `String` is sent as it is;
/// any other value is JSON-encoded, so a `Map` arrives as `{"name":"Ada"}`
/// and a number as `3`. Keep the [id] to update or remove the entry later.
// The default id is generated, so the constructor can't be const.
// ignore: prefer_const_constructors_in_immutables
class AgentContextEntry({
  /// Tells the agent what [value] is.
  required final String description,

  /// The data shared with the agent: a `String` (sent as it is) or a
  /// JSON-encodable value (sent JSON-encoded).
  ///
  /// Pre-encode it yourself and pass the resulting `String` to control the
  /// exact text the agent receives.
  final Object? value,

  /// Ids of the agents the entry is sent to, or `null` (the default) to send
  /// it to every agent. An empty set sends it to none.
  final Set<String>? agentIds,
  String? id,
}) extends Equatable {
  /// Creates an entry; a random [id] is generated when none is given.
  this;

  /// Identifies the entry in `ContextUpdated` and `ContextRemoved`.
  final String id = id ?? const Uuid().v4();

  /// Returns a copy with [value] replaced.
  AgentContextEntry copyWith({required Object? value}) => AgentContextEntry(
    id: id,
    description: description,
    value: value,
    agentIds: agentIds,
  );

  @override
  List<Object?> get props => [id, description, value, agentIds];
}
