// cspell:ignore realtime
/// The kind of request of a `ThreadsException`.
enum ThreadsErrorCode {
  /// Listing the threads failed.
  listFailed,

  /// Renaming, archiving, unarchiving or deleting a thread failed.
  mutationFailed,

  /// The runtime didn't answer in time.
  requestTimeout,

  /// Asking for the credentials of the thread metadata channel failed.
  subscribeFailed,

  /// The thread metadata channel can't be followed: the runtime has no
  /// real-time service, or its socket failed too many times in a row.
  realtimeUnavailable,
}
