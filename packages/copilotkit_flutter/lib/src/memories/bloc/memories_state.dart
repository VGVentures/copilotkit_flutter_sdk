part of 'memories_bloc.dart';

/// What a memories UI shows: the [memories] of the user and what is going on
/// with them.
///
/// The memories change as the user's operations finish, not live: a memory
/// another device saves shows after the next [MemoriesRequested].
final class const MemoriesState({
  /// The memories of the user, newest first.
  final List<Memory> memories = const [],

  /// The memories the last recall found, best first, or none.
  final List<Memory> recalled = const [],

  /// Whether the memories are loading.
  final bool isLoading = false,

  /// Whether the last recall is running.
  final bool isRecalling = false,

  /// Whether [memories] was loaded with the retired memories included.
  ///
  /// Retiring a memory then marks it retired instead of removing it, as the
  /// next load would show it.
  final bool includeInvalidated = false,

  /// Whether the runtime has memory to offer.
  ///
  /// It is `false` when the runtime has no memory configured or the app has
  /// no access, which is not an error: show that memory isn't available. It
  /// is `true` until the runtime says otherwise.
  final bool isAvailable = true,

  /// The failure of the last operation, or `null`.
  ///
  /// A [MemoryException], or a [MemoryValidationException] when the memory
  /// to save broke a limit.
  final Object? error,

  /// How many saves, replacements and retirements are running.
  final int inFlightMutationCount = 0,

  /// What the runtime did with the last memory saved or superseded, or
  /// `null` after a failure or a retirement.
  ///
  /// Check [MemoryMutationOutcome.isAbsorbed] to tell the user a memory was
  /// merged into an existing one.
  final MemoryMutationOutcome? lastOutcome,
}) extends Equatable {
  /// Creates the state of a memories UI.
  this;

  /// Whether a save, replacement or retirement is running.
  bool get isMutating => inFlightMutationCount > 0;

  /// Returns this state with the given fields replaced.
  ///
  /// A nullable field takes a function, so it can be set to `null`.
  MemoriesState copyWith({
    List<Memory>? memories,
    List<Memory>? recalled,
    bool? isLoading,
    bool? isRecalling,
    bool? includeInvalidated,
    bool? isAvailable,
    Object? Function()? error,
    int? inFlightMutationCount,
    MemoryMutationOutcome? Function()? lastOutcome,
  }) => MemoriesState(
    memories: memories ?? this.memories,
    recalled: recalled ?? this.recalled,
    isLoading: isLoading ?? this.isLoading,
    isRecalling: isRecalling ?? this.isRecalling,
    includeInvalidated: includeInvalidated ?? this.includeInvalidated,
    isAvailable: isAvailable ?? this.isAvailable,
    error: error == null ? this.error : error(),
    inFlightMutationCount: inFlightMutationCount ?? this.inFlightMutationCount,
    lastOutcome: lastOutcome == null ? this.lastOutcome : lastOutcome(),
  );

  @override
  List<Object?> get props => [
    memories,
    recalled,
    isLoading,
    isRecalling,
    includeInvalidated,
    isAvailable,
    error,
    inFlightMutationCount,
    lastOutcome,
  ];
}
