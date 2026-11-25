// cspell:ignore realtime
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:equatable/equatable.dart';

part 'threads_event.dart';
part 'threads_state.dart';

/// Drives a threads UI from a [CopilotKitClient].
///
/// Turns [ThreadsRequested], [ThreadsNextPageRequested], [ThreadRenamed],
/// [ThreadArchived], [ThreadUnarchived] and [ThreadDeleted] into calls on the
/// client's [CopilotKitClient.threads], and applies what the runtime answers
/// to [ThreadsState]. A deletion is the one change applied before the answer:
/// it is undone if the runtime rejects it.
///
/// It reads the routes the runtime has once per [ThreadsRequested], and
/// leaves changes alone when the runtime has no thread mutations (see
/// [ThreadsState.canMutate]).
///
/// When the runtime has real-time thread metadata, each [ThreadsRequested]
/// that loads the list then follows it live with
/// [CopilotKitClient.watchThreads] until the next [ThreadsRequested] or
/// [close]: threads created, renamed, archived or deleted on any device show
/// up without a refresh. If the channel fails for good, the list stays as it
/// was last updated.
class ThreadsBloc({
  required final CopilotKitClient _client,
  required final String _agentId,
  final bool _includeArchived = false,
  final int? _limit,
}) extends Bloc<ThreadsEvent, ThreadsState> {
  /// Creates a bloc that drives a threads UI for the threads of the agent
  /// `agentId`, as listed through `client`.
  ///
  /// It also lists archived threads when `includeArchived`, and loads pages
  /// of `limit` threads, as many as the runtime chooses when it is `null`.
  this : super(const ThreadsState()) {
    on<ThreadsRequested>(_onRequested, transformer: restartable());
    on<ThreadsNextPageRequested>(_onNextPage, transformer: droppable());
    on<ThreadRenamed>(_onRenamed, transformer: concurrent());
    on<ThreadArchived>(_onArchived, transformer: concurrent());
    on<ThreadUnarchived>(_onUnarchived, transformer: concurrent());
    on<ThreadDeleted>(_onDeleted, transformer: concurrent());
  }

  Future<void> _onRequested(
    ThreadsRequested event,
    Emitter<ThreadsState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        error: () => null,
        fetchMoreError: () => null,
      ),
    );
    final endpoints = await _client.threadEndpoints();
    emit(state.copyWith(canMutate: endpoints.mutations));
    if (!endpoints.list) {
      return emit(
        state.copyWith(
          threads: const [],
          isLoading: false,
          isAvailable: false,
          nextCursor: () => null,
        ),
      );
    }
    final ThreadPage page;
    try {
      page = await _client.threads.list(
        agentId: _agentId,
        includeArchived: _includeArchived,
        limit: _limit,
      );
    } on Object catch (error) {
      return emit(state.copyWith(isLoading: false, error: () => error));
    }
    emit(
      state.copyWith(
        threads: page.threads,
        isLoading: false,
        isAvailable: true,
        nextCursor: () => page.nextCursor,
      ),
    );
    final joinCode = page.joinCode;
    if (!endpoints.realtimeMetadata || joinCode == null) return;
    // Runs until the next ThreadsRequested restarts this handler, which
    // cancels it, so events of an older list never reach a newer one.
    await emit.forEach(
      _client.watchThreads(joinCode),
      onData: (event) => state.copyWith(threads: _applied(event)),
      // The channel gave up: the list stays as it was last updated.
      onError: (_, _) => state,
    );
  }

  Future<void> _onNextPage(
    ThreadsNextPageRequested event,
    Emitter<ThreadsState> emit,
  ) async {
    final cursor = state.nextCursor;
    // While the first page loads, the cursor belongs to the list being
    // replaced.
    if (cursor == null || state.isLoading) return;
    emit(state.copyWith(isFetchingNextPage: true, fetchMoreError: () => null));
    try {
      final page = await _client.threads.list(
        agentId: _agentId,
        includeArchived: _includeArchived,
        limit: _limit,
        cursor: cursor,
      );
      // A refresh finished meanwhile: this page continues a list that is gone.
      if (state.nextCursor != cursor) {
        return emit(state.copyWith(isFetchingNextPage: false));
      }
      final known = {for (final thread in state.threads) thread.id};
      emit(
        state.copyWith(
          threads: [
            ...state.threads,
            for (final thread in page.threads)
              if (!known.contains(thread.id)) thread,
          ],
          isFetchingNextPage: false,
          nextCursor: () => page.nextCursor,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          isFetchingNextPage: false,
          fetchMoreError: state.nextCursor == cursor ? () => error : null,
        ),
      );
    }
  }

  Future<void> _onRenamed(ThreadRenamed event, Emitter<ThreadsState> emit) =>
      _mutate(emit, () async {
        final renamed = await _client.threads.rename(
          agentId: _agentId,
          threadId: event.threadId,
          name: event.name,
        );
        return _replaced(renamed);
      });

  Future<void> _onArchived(ThreadArchived event, Emitter<ThreadsState> emit) =>
      _mutate(emit, () async {
        await _client.threads.archive(
          agentId: _agentId,
          threadId: event.threadId,
        );
        return _includeArchived
            ? [
                for (final thread in state.threads)
                  if (thread.id == event.threadId)
                    thread.copyWith(archived: true)
                  else
                    thread,
              ]
            : _without(event.threadId);
      });

  Future<void> _onUnarchived(
    ThreadUnarchived event,
    Emitter<ThreadsState> emit,
  ) => _mutate(emit, () async {
    final unarchived = await _client.threads.unarchive(
      agentId: _agentId,
      threadId: event.threadId,
    );
    return _replaced(unarchived);
  });

  Future<void> _onDeleted(
    ThreadDeleted event,
    Emitter<ThreadsState> emit,
  ) async {
    if (!_canMutate(emit)) return;
    _deleting.add(event.threadId);
    final index = state.threads.indexWhere((t) => t.id == event.threadId);
    final removed = index == -1 ? null : state.threads[index];
    emit(
      state.copyWith(
        threads: _without(event.threadId),
        inFlightMutationCount: state.inFlightMutationCount + 1,
        error: () => null,
      ),
    );
    try {
      await _client.threads.delete(agentId: _agentId, threadId: event.threadId);
      // A refresh may have brought the thread back while the delete ran.
      emit(
        state.copyWith(
          threads: _without(event.threadId),
          inFlightMutationCount: state.inFlightMutationCount - 1,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          // A refresh may have brought it back already.
          threads:
              removed == null || state.threads.any((t) => t.id == removed.id)
              ? null
              : _restored(removed, index),
          inFlightMutationCount: state.inFlightMutationCount - 1,
          error: () => error,
        ),
      );
    } finally {
      _deleting.remove(event.threadId);
    }
  }

  /// The ids of the threads whose deletion is running. A live event for one
  /// of them must not bring it back before the runtime answers.
  final _deleting = <String>{};

  /// The threads after the live [event]: a deletion, or an archive the list
  /// doesn't show, removes the thread; any other change puts the thread in
  /// place or adds it, newest first.
  ///
  /// The real-time service may push an event more than once, which changes
  /// nothing the second time.
  List<ThreadRecord> _applied(ThreadMetadataEvent event) {
    final thread = event.thread;
    if (event.operation == ThreadMetadataOperation.deleted) {
      return _without(event.threadId);
    }
    if (thread == null ||
        thread.agentId != _agentId ||
        _deleting.contains(thread.id)) {
      return state.threads;
    }
    if (thread.archived && !_includeArchived) return _without(thread.id);
    final known = state.threads.any((t) => t.id == thread.id);
    return [
      ...known ? _replaced(thread) : [...state.threads, thread],
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Runs [mutation] while counting it as in flight, then puts the list it
  /// returns in the state.
  Future<void> _mutate(
    Emitter<ThreadsState> emit,
    Future<List<ThreadRecord>> Function() mutation,
  ) async {
    if (!_canMutate(emit)) return;
    emit(
      state.copyWith(
        inFlightMutationCount: state.inFlightMutationCount + 1,
        error: () => null,
      ),
    );
    try {
      final threads = await mutation();
      emit(
        state.copyWith(
          threads: threads,
          inFlightMutationCount: state.inFlightMutationCount - 1,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          inFlightMutationCount: state.inFlightMutationCount - 1,
          error: () => error,
        ),
      );
    }
  }

  /// Whether the runtime can change threads. When it can't, puts an error in
  /// the state.
  bool _canMutate(Emitter<ThreadsState> emit) {
    if (state.canMutate) return true;
    emit(
      state.copyWith(
        error: () =>
            UnsupportedError('The runtime does not support changing threads.'),
      ),
    );
    return false;
  }

  List<ThreadRecord> _without(String id) => [
    for (final thread in state.threads)
      if (thread.id != id) thread,
  ];

  /// The threads with [thread] in place of the one with its id, if the list
  /// has one.
  List<ThreadRecord> _replaced(ThreadRecord thread) => [
    for (final known in state.threads)
      if (known.id == thread.id) thread else known,
  ];

  /// The threads with [thread] back at [index], or at the end when the list
  /// is shorter now.
  List<ThreadRecord> _restored(ThreadRecord thread, int index) =>
      [...state.threads]..insert(index.clamp(0, state.threads.length), thread);
}
