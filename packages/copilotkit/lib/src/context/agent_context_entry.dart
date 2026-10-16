/// A piece of app data shared with the agent.
///
/// Created by `CopilotKitClient.addContext`. Every run sends all live entries
/// as `RunAgentInput.context`, with [value] JSON-encoded.
abstract interface class AgentContextEntry {
  /// Tells the agent what [value] is.
  String get description;

  /// Current value; must be JSON-encodable.
  Object? get value;

  /// Replaces [value]; the next run sends the new value.
  void update(Object? value);

  /// Removes the entry; later runs no longer send it.
  void remove();
}
