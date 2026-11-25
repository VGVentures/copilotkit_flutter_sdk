// cspell:ignore realtime
/// The code of a `MemoryException`: the ones `@copilotkit/core` uses, plus
/// [realtimeUnavailable], which core has no code for.
enum MemoryErrorCode {
  /// Listing the memories failed.
  listFailed('MEMORY_LIST_FAILED'),

  /// Recalling memories failed.
  recallFailed('MEMORY_RECALL_FAILED'),

  /// Fetching the credentials for live updates failed.
  credentialsFailed('MEMORY_CREDENTIALS_FAILED'),

  /// Saving, superseding or retiring a memory failed.
  mutationFailed('MEMORY_MUTATION_FAILED'),

  /// The runtime didn't answer in time.
  requestTimeout('MEMORY_REQUEST_TIMEOUT'),

  /// Live changes can't be followed: the runtime has no real-time service,
  /// or the channel failed too many times in a row.
  realtimeUnavailable('MEMORY_REALTIME_UNAVAILABLE');

  new(this.wireName);

  /// The code as the other CopilotKit SDKs spell it, e.g.
  /// `MEMORY_LIST_FAILED`.
  final String wireName;
}
