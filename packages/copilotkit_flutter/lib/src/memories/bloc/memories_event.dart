part of 'memories_bloc.dart';

/// Events handled by [MemoriesBloc].
sealed class MemoriesEvent extends Equatable {
  const new();
}

/// Load the memories of the user, replacing the ones in the state.
///
/// Also refreshes them. A request that arrives while another loads replaces
/// it.
final class const MemoriesRequested({
  /// Whether to include the memories that were retired.
  final bool includeInvalidated = false,
}) extends MemoriesEvent {
  /// Creates the event for loading the memories.
  this;

  @override
  List<Object?> get props => [includeInvalidated];
}

/// Recall the memories that best match [query]; they replace
/// [MemoriesState.recalled].
///
/// A recall that arrives while another is running replaces it.
final class const MemoriesRecalled(
  /// What to look for.
  final String query, {

  /// The most memories to recall. [MemoriesClient.defaultRecallLimit] when
  /// `null`, and never more than [MemoriesClient.maxRecallLimit].
  final int? limit,

  /// Narrows the recall to one scope.
  final MemoryScope? scope,
}) extends MemoriesEvent {
  /// Creates the event for recalling the memories that match [query].
  this;

  @override
  List<Object?> get props => [query, limit, scope];
}

/// Save [memory].
///
/// The runtime may merge a near-duplicate into an existing memory instead:
/// see [MemoriesState.lastOutcome].
final class const MemorySaved(
  /// The memory to save.
  final NewMemory memory,
) extends MemoriesEvent {
  /// Creates the event for saving [memory].
  this;

  @override
  List<Object?> get props => [memory];
}

/// Replace the memory [id] with [memory].
///
/// The replacement has another id. It is a full replacement, so
/// [NewMemory.sourceThreadIds] left out are reset, not kept.
final class const MemorySuperseded(
  /// The id of the memory to replace.
  final String id,

  /// The memory that replaces it.
  final NewMemory memory,
) extends MemoriesEvent {
  /// Creates the event for replacing the memory [id] with [memory].
  this;

  @override
  List<Object?> get props => [id, memory];
}

/// Retire the memory [id]: it leaves the list and the recalled memories.
final class const MemoryRetired(
  /// The id of the memory to retire.
  final String id,
) extends MemoriesEvent {
  /// Creates the event for retiring the memory [id].
  this;

  @override
  List<Object?> get props => [id];
}
