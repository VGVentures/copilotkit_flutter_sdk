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

  Future<void> _onRequested(
    MemoriesRequested event,
    Emitter<MemoriesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: () => null));
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
      emit(_unavailable());
    } on Object catch (error) {
      emit(state.copyWith(isLoading: false, error: () => error));
    }
  }

  Future<void> _onRecalled(
    MemoriesRecalled event,
    Emitter<MemoriesState> emit,
  ) async {
    // Bloc emits the first state even when it equals the current one.
    if (state.error != null) emit(state.copyWith(error: () => null));
    try {
      final recalled = await _client.recall(
        event.query,
        limit: event.limit,
        scope: event.scope,
      );
      emit(state.copyWith(recalled: recalled, isAvailable: true));
    } on MemoryUnavailableException {
      emit(_unavailable());
    } on Object catch (error) {
      emit(state.copyWith(error: () => error));
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
      emit(
        state.copyWith(
          memories: outcome == null
              ? _without(state.memories, onRetired)
              : onOutcome!(outcome),
          recalled: _without(state.recalled, onRetired),
          inFlightMutationCount: state.inFlightMutationCount - 1,
          isAvailable: true,
          error: () => null,
          lastOutcome: () => outcome,
        ),
      );
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
    isAvailable: false,
    error: () => null,
    lastOutcome: () => null,
  );

  List<Memory> _without(List<Memory> memories, String? id) => [
    for (final memory in memories)
      if (memory.id != id) memory,
  ];

  List<Memory> _withMemory(Memory memory, {String? replacing}) {
    final memories = _without(state.memories, replacing);
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index == -1) return [memory, ...memories];
    return [...memories]..[index] = memory;
  }
}
