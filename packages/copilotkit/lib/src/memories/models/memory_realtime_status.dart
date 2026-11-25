// cspell:ignore realtime
/// Whether a memories list follows changes live, as `@copilotkit/core`'s
/// `realtimeStatus` says it.
enum MemoryRealtimeStatus {
  /// Asking for credentials and joining the channel.
  connecting,

  /// Joined: changes show up as they happen.
  connected,

  /// Live changes can't be followed. The list is a snapshot from when it was
  /// last updated; don't show it as live.
  unavailable,
}
