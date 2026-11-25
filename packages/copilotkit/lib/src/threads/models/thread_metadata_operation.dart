/// What happened to a thread, in a `ThreadMetadataEvent`.
enum ThreadMetadataOperation {
  /// The thread was created, by its first run.
  created,

  /// The thread got a new name, from the user or from the runtime.
  renamed,

  /// The thread was archived.
  archived,

  /// The thread was brought back from the archive.
  unarchived,

  /// Something else about the thread changed.
  updated,

  /// The thread was deleted.
  deleted,
}
