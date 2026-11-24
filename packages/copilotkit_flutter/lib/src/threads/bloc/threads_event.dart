part of 'threads_bloc.dart';

/// Events handled by [ThreadsBloc].
sealed class ThreadsEvent extends Equatable {
  const new();
}

/// Load the first page of the agent's threads, replacing the ones in the
/// state.
///
/// Also refreshes them, and reads which routes the runtime has. A request
/// that arrives while another loads replaces it.
final class const ThreadsRequested() extends ThreadsEvent {
  /// Creates the event for loading the threads.
  this;

  @override
  List<Object?> get props => [];
}

/// Load the page after the last one in the state, and add it to the list.
///
/// Does nothing while a page is loading or when the last page is already in
/// the state.
final class const ThreadsNextPageRequested() extends ThreadsEvent {
  /// Creates the event for loading the next page.
  this;

  @override
  List<Object?> get props => [];
}

/// Give a thread a name.
///
/// The state changes once the runtime has confirmed.
final class const ThreadRenamed(
  /// The thread to rename.
  final String threadId,

  /// Its new name.
  final String name,
) extends ThreadsEvent {
  /// Creates the event for renaming [threadId] to [name].
  this;

  @override
  List<Object?> get props => [threadId, name];
}

/// Archive a thread.
///
/// The state changes once the runtime has confirmed: the thread leaves the
/// list, or stays marked as archived when the bloc lists archived threads.
final class const ThreadArchived(
  /// The thread to archive.
  final String threadId,
) extends ThreadsEvent {
  /// Creates the event for archiving [threadId].
  this;

  @override
  List<Object?> get props => [threadId];
}

/// Bring an archived thread back.
///
/// The state changes once the runtime has confirmed, and only when the thread
/// is in the list, which it is only for a bloc that lists archived threads.
final class const ThreadUnarchived(
  /// The thread to unarchive.
  final String threadId,
) extends ThreadsEvent {
  /// Creates the event for unarchiving [threadId].
  this;

  @override
  List<Object?> get props => [threadId];
}

/// Delete a thread for good.
///
/// The thread leaves the list at once, and comes back to its place if the
/// runtime rejects the deletion.
final class const ThreadDeleted(
  /// The thread to delete.
  final String threadId,
) extends ThreadsEvent {
  /// Creates the event for deleting [threadId].
  this;

  @override
  List<Object?> get props => [threadId];
}
