// cspell:ignore realtime
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:equatable/equatable.dart';

part 'memories_event.dart';
part 'memories_state.dart';

/// Drives a memories UI from a [MemoriesClient].
///
/// Turns [MemoriesRequested], [MemoriesRecalled], [MemorySaved],
/// [MemorySuperseded] and [MemoryRetired] into calls on the client, and
/// applies what the runtime answers to [MemoriesState]: it never guesses.
/// A runtime without memory sets [MemoriesState.isAvailable] to `false`
/// instead of an error.
///
/// Each [MemoriesRequested] that loads the list then follows it live with
/// [MemoriesClient.watch] until the next one or [close], and reports how in
/// [MemoriesState.realtimeStatus]: memories saved, replaced or retired by
/// any device or agent run show up without a refresh.
///
/// Pass `CopilotKitClient.memories` as the client, so memory requests carry
/// the same headers as the runs.
class MemoriesBloc({required final MemoriesClient _client})
    extends Bloc<MemoriesEvent, MemoriesState> {
  /// Creates a bloc that drives a memories UI from `client`.
  this : super(const MemoriesState()) {
    on<MemoriesRequested>(_onRequested, transformer: restartable());
    on<MemoriesRecalled>(_onRecalled, transformer: restartable());
    on<MemorySaved>(_onSaved, transformer: concurrent());
    on<MemorySuperseded>(_onSuperseded, transformer: concurrent());
    on<MemoryRetired>(_onRetired, transformer: concurrent());
  }

  /// The ids of the memories known to be retired. The service repeats
  /// events, so a stale `created` may arrive after a memory's `invalidated`
  /// and must not bring it back. A retired id never comes back: a
  /// replacement gets a new one.
  final _retiredIds = <String>{};

  Future<void> _onRequested(
    MemoriesRequested event,
    Emitter<MemoriesState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        includeInvalidated: event.includeInvalidated,
        realtimeStatus: MemoryRealtimeStatus.connecting,
        error: () => null,
      ),
    );
    try {
      final memories = await _client.list(
        includeInvalidated: event.includeInvalidated,
      );
      emit(
        state.copyWith(
          memories: memories,
          isLoading: false,
          isAvailable: true,
          error: () => null,
        ),
      );
    } on MemoryUnavailableException {
      return emit(_unavailable());
    } on Object catch (error) {
      return emit(
        state.copyWith(
          isLoading: false,
          realtimeStatus: MemoryRealtimeStatus.unavailable,
          error: () => error,
        ),
      );
    }
    // Runs until the next MemoriesRequested restarts this handler, which
    // cancels it, so events of an older list never reach a newer one.
    await emit.forEach(
      _client.watch(
        // The handler is still running while the channel is followed. Once
        // the next MemoriesRequested or close ends it, emit is done, so the
        // join of an older list changes nothing.
        onConnected: () {
          if (emit.isDone) return;
          emit(state.copyWith(realtimeStatus: MemoryRealtimeStatus.connected));
        },
      ),
      onData: _applied,
      onError: (_, _) =>
          state.copyWith(realtimeStatus: MemoryRealtimeStatus.unavailable),
    );
  }

  /// The state after the live [event]: a created or updated memory is put
  /// in place or added first, an invalidated one leaves the list (or is
  /// marked retired when retired memories are listed) and the recall.
  MemoriesState _applied(MemoryMetadataEvent event) {
    final memory = event.memory;
    if (event.operation == MemoryMetadataOperation.invalidated) {
      _retiredIds.add(event.memoryId);
      return state.copyWith(
        memories: _retired(state.memories, event.memoryId),
        recalled: _without(state.recalled, event.memoryId),
      );
    }
    if (memory == null || _retiredIds.contains(memory.id)) return state;
    return state.copyWith(memories: _withMemory(memory));
  }

  Future<void> _onRecalled(
    MemoriesRecalled event,
    Emitter<MemoriesState> emit,
  ) async {
    // Bloc emits the first state even when it equals the current one.
    emit(state.copyWith(isRecalling: true, error: () => null));
    try {
      final recalled = await _client.recall(
        event.query,
        limit: event.limit,
        scope: event.scope,
      );
      emit(
        state.copyWith(
          recalled: recalled,
          isRecalling: false,
          isAvailable: true,
        ),
      );
    } on MemoryUnavailableException {
      emit(_unavailable());
    } on Object catch (error) {
      emit(state.copyWith(isRecalling: false, error: () => error));
    }
  }

  Future<void> _onSaved(MemorySaved event, Emitter<MemoriesState> emit) =>
      _mutate(
        emit,
        () => _client.save(event.memory),
        onOutcome: (outcome) => _withMemory(outcome.memory),
      );

  Future<void> _onSuperseded(
    MemorySuperseded event,
    Emitter<MemoriesState> emit,
  ) => _mutate(
    emit,
    () => _client.supersede(event.id, event.memory),
    onOutcome: (outcome) =>
        _withMemory(outcome.memory, replacing: outcome.retiredId),
  );

  Future<void> _onRetired(MemoryRetired event, Emitter<MemoriesState> emit) =>
      _mutate(emit, () async {
        await _client.retire(event.id);
        return null;
      }, onRetired: event.id);

  /// Runs [mutation] while counting it as in flight, then applies its
  /// result to the state.
  ///
  /// A save or supersede puts [onOutcome]'s memories in the list. A
  /// retirement, which has no outcome, removes [onRetired] instead.
  Future<void> _mutate(
    Emitter<MemoriesState> emit,
    Future<MemoryMutationOutcome?> Function() mutation, {
    List<Memory> Function(MemoryMutationOutcome outcome)? onOutcome,
    String? onRetired,
  }) async {
    emit(
      state.copyWith(inFlightMutationCount: state.inFlightMutationCount + 1),
    );
    try {
      final outcome = await mutation();
      // A supersede retires a memory too, so it leaves the recall as well.
      final retiredId = onRetired ?? outcome?.retiredId;
      if (retiredId != null) _retiredIds.add(retiredId);
      emit(
        state.copyWith(
          memories: outcome == null
              ? _retired(state.memories, onRetired)
              : onOutcome!(outcome),
          recalled: _without(state.recalled, retiredId),
          inFlightMutationCount: state.inFlightMutationCount - 1,
          isAvailable: true,
          error: () => null,
          lastOutcome: () => outcome,
        ),
      );
      // A list still loading may have been read before this change: load it
      // again, which also drops the stale one (restartable).
      if (state.isLoading) {
        add(MemoriesRequested(includeInvalidated: state.includeInvalidated));
      }
    } on MemoryUnavailableException {
      emit(
        _unavailable().copyWith(
          inFlightMutationCount: state.inFlightMutationCount - 1,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          inFlightMutationCount: state.inFlightMutationCount - 1,
          error: () => error,
          lastOutcome: () => null,
        ),
      );
    }
  }

  MemoriesState _unavailable() => state.copyWith(
    memories: const [],
    recalled: const [],
    isLoading: false,
    isRecalling: false,
    isAvailable: false,
    realtimeStatus: MemoryRealtimeStatus.unavailable,
    error: () => null,
    lastOutcome: () => null,
  );

  List<Memory> _without(List<Memory> memories, String? id) => [
    for (final memory in memories)
      if (memory.id != id) memory,
  ];

  /// The list without the retired memory [id], or with it marked retired
  /// when the list was loaded with the retired memories included.
  List<Memory> _retired(List<Memory> memories, String? id) {
    if (!state.includeInvalidated) return _without(memories, id);
    return [
      for (final memory in memories)
        if (memory.id == id)
          Memory(
            id: memory.id,
            kind: memory.kind,
            scope: memory.scope,
            content: memory.content,
            sourceThreadIds: memory.sourceThreadIds,
            score: memory.score,
            invalidatedAt: DateTime.now().toUtc(),
          )
        else
          memory,
    ];
  }

  List<Memory> _withMemory(Memory memory, {String? replacing}) {
    final memories = _retired(state.memories, replacing);
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index == -1) return [memory, ...memories];
    return [...memories]..[index] = memory;
  }
}
