/// The code of a `MemoryException`, the same ones `@copilotkit/core` uses.
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
  requestTimeout('MEMORY_REQUEST_TIMEOUT');

  new(this.wireName);

  /// The code as the other CopilotKit SDKs spell it, e.g.
  /// `MEMORY_LIST_FAILED`.
  final String wireName;
}
