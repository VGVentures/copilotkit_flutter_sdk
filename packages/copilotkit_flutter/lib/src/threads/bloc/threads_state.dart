part of 'threads_bloc.dart';

/// What a threads UI shows: the [threads] of an agent and what is going on
/// with them.
///
/// The threads change as the user's operations finish and, on a runtime with
/// real-time thread metadata, live as any device changes them. Without it, a
/// thread another device changes shows after the next [ThreadsRequested].
final class const ThreadsState({
  /// The threads loaded so far, newest first.
  final List<ThreadRecord> threads = const [],

  /// Whether the first page is loading.
  final bool isLoading = false,

  /// Whether a later page is loading.
  final bool isFetchingNextPage = false,

  /// Whether the runtime can list threads.
  ///
  /// It is `false` when the runtime has no thread routes, which is not an
  /// error: show that threads aren't available. It is `true` until the
  /// runtime says otherwise.
  final bool isAvailable = true,

  /// Whether the runtime can change threads: rename, archive and delete.
  ///
  /// It is `false` until the first [ThreadsRequested] has read the runtime's
  /// routes, and stays `false` for a runtime without Intelligence. Hide the
  /// actions then: the bloc ignores them and sets [error].
  final bool canMutate = false,

  /// The failure of loading the first page or of a change, or `null`.
  ///
  /// A `ThreadsException`, or an [UnsupportedError] for a change the runtime
  /// can't make.
  final Object? error,

  /// The failure of loading the last page requested, or `null`.
  ///
  /// It leaves the threads loaded so far in place.
  final Object? fetchMoreError,

  /// The cursor of the page after the last one loaded, or `null` on the last
  /// page.
  final String? nextCursor,

  /// How many renames, archives and deletions are running.
  final int inFlightMutationCount = 0,
}) extends Equatable {
  /// Creates the state of a threads UI.
  this;

  /// Whether another page follows the threads loaded.
  bool get hasNextPage => nextCursor != null;

  /// Whether a rename, archive or deletion is running.
  bool get isMutating => inFlightMutationCount > 0;

  /// Returns this state with the given fields replaced.
  ///
  /// A nullable field takes a function, so it can be set to `null`.
  ThreadsState copyWith({
    List<ThreadRecord>? threads,
    bool? isLoading,
    bool? isFetchingNextPage,
    bool? isAvailable,
    bool? canMutate,
    Object? Function()? error,
    Object? Function()? fetchMoreError,
    String? Function()? nextCursor,
    int? inFlightMutationCount,
  }) => ThreadsState(
    threads: threads ?? this.threads,
    isLoading: isLoading ?? this.isLoading,
    isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
    isAvailable: isAvailable ?? this.isAvailable,
    canMutate: canMutate ?? this.canMutate,
    error: error == null ? this.error : error(),
    fetchMoreError: fetchMoreError == null
        ? this.fetchMoreError
        : fetchMoreError(),
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
    inFlightMutationCount: inFlightMutationCount ?? this.inFlightMutationCount,
  );

  @override
  List<Object?> get props => [
    threads,
    isLoading,
    isFetchingNextPage,
    isAvailable,
    canMutate,
    error,
    fetchMoreError,
    nextCursor,
    inFlightMutationCount,
  ];
}
