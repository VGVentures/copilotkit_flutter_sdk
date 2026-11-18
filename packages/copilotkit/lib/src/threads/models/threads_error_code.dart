/// The kind of request of a `ThreadsException`.
enum ThreadsErrorCode {
  /// Listing the threads failed.
  listFailed,

  /// Renaming, archiving, unarchiving or deleting a thread failed.
  mutationFailed,

  /// The runtime didn't answer in time.
  requestTimeout,
}
