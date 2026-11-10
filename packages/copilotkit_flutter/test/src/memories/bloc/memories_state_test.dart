import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const memory = Memory(
    id: 'm1',
    kind: MemoryKind.topical,
    scope: MemoryScope.user,
    content: 'c',
    sourceThreadIds: [],
  );
  const outcome = MemoryMutationOutcome(memory: memory);

  group(MemoriesState, () {
    test('starts available and idle', () {
      const state = MemoriesState();

      expect(state.memories, isEmpty);
      expect(state.recalled, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.isAvailable, isTrue);
      expect(state.error, isNull);
      expect(state.isMutating, isFalse);
      expect(state.lastOutcome, isNull);
    });

    test('is mutating while an operation is in flight', () {
      expect(const MemoriesState(inFlightMutationCount: 2).isMutating, isTrue);
    });

    group('copyWith', () {
      test('keeps every field by default', () {
        const state = MemoriesState(
          memories: [memory],
          recalled: [memory],
          isLoading: true,
          isAvailable: false,
          error: 'boom',
          inFlightMutationCount: 1,
          lastOutcome: outcome,
        );

        expect(state.copyWith(), state);
      });

      test('replaces the given fields', () {
        final state = const MemoriesState().copyWith(
          memories: [memory],
          recalled: [memory],
          isLoading: true,
          isAvailable: false,
          error: () => 'boom',
          inFlightMutationCount: 1,
          lastOutcome: () => outcome,
        );

        expect(
          state,
          const MemoriesState(
            memories: [memory],
            recalled: [memory],
            isLoading: true,
            isAvailable: false,
            error: 'boom',
            inFlightMutationCount: 1,
            lastOutcome: outcome,
          ),
        );
      });

      test('clears the nullable fields', () {
        final state = const MemoriesState(
          error: 'boom',
          lastOutcome: outcome,
        ).copyWith(error: () => null, lastOutcome: () => null);

        expect(state, const MemoriesState());
      });
    });
  });
}
