/// Who can see a memory.
enum MemoryScope {
  /// Only the user the memory is about. The default.
  user('user'),

  /// Everyone in the project.
  project('project');

  new(this.wireName);

  /// The name of the scope in the runtime's JSON.
  final String wireName;

  /// Returns the scope named [wireName] in the runtime's JSON, or `null` when
  /// the runtime sends a name this SDK doesn't know.
  static MemoryScope? fromWireName(Object? wireName) =>
      values.where((scope) => scope.wireName == wireName).firstOrNull;
}
