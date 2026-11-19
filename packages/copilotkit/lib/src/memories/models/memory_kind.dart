/// What a memory is about.
enum MemoryKind {
  /// A lasting fact about a subject, like a preference.
  topical('topical'),

  /// Something that happened at a point in time.
  episodic('episodic'),

  /// How the agent should behave or do something.
  operational('operational');

  new(this.wireName);

  /// The name of the kind in the runtime's JSON.
  final String wireName;

  /// Returns the kind named [wireName] in the runtime's JSON, or `null` when
  /// the runtime sends a name this SDK doesn't know.
  static MemoryKind? fromWireName(Object? wireName) =>
      values.where((kind) => kind.wireName == wireName).firstOrNull;
}
