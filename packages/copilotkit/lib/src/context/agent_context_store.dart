import 'package:copilotkit/src/context/models/agent_context_entry.dart';
import 'package:copilotkit/src/json/json.dart';

/// The app data shared with the agent, in the order it was added.
///
/// Entries come and go while the app runs, so this is mutable: a documented
/// exception to the immutability rule.
class AgentContextStore() {
  /// Creates an empty store.
  this;

  final _entries = <AgentContextEntry>[];

  /// The entries, oldest first.
  ///
  /// A read-only copy.
  List<AgentContextEntry> get entries => List.unmodifiable(_entries);

  /// Adds [entry].
  void add(AgentContextEntry entry) => _entries.add(entry);

  /// Replaces the value of the entry [id].
  ///
  /// Does nothing if there is none.
  void update(String id, JsonEncodable value) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return;
    _entries[index] = _entries[index].copyWith(value: value);
  }

  /// Removes the entry [id].
  ///
  /// Does nothing if there is none.
  void remove(String id) => _entries.removeWhere((entry) => entry.id == id);
}
