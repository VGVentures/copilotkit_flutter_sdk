/// What happened to a memory, in a `MemoryMetadataEvent`.
enum MemoryMetadataOperation {
  /// The memory was saved, by the user, the app or the agent, or it
  /// replaced another one.
  created,

  /// The memory changed in place.
  updated,

  /// The memory was retired or replaced.
  invalidated,
}
