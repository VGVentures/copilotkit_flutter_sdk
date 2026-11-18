import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(ThreadsState, () {
    test('starts available, with nothing loaded and nothing changing', () {
      const state = ThreadsState();

      expect(state.threads, isEmpty);
      expect(state.isAvailable, isTrue);
      expect(state.canMutate, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.isFetchingNextPage, isFalse);
      expect(state.isMutating, isFalse);
      expect(state.hasNextPage, isFalse);
    });

    test('has a next page while it holds a cursor', () {
      expect(const ThreadsState(nextCursor: 'c').hasNextPage, isTrue);
    });

    test('is mutating while a change is in flight', () {
      expect(const ThreadsState(inFlightMutationCount: 2).isMutating, isTrue);
    });

    test('copies with replaced fields', () {
      final thread = ThreadRecord(
        id: 't',
        agentId: 'default',
        archived: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final copy = const ThreadsState().copyWith(
        threads: [thread],
        isLoading: true,
        isFetchingNextPage: true,
        isAvailable: false,
        canMutate: true,
        error: () => 'e',
        fetchMoreError: () => 'f',
        nextCursor: () => 'c',
        inFlightMutationCount: 3,
      );

      expect(
        copy,
        ThreadsState(
          threads: [thread],
          isLoading: true,
          isFetchingNextPage: true,
          isAvailable: false,
          canMutate: true,
          error: 'e',
          fetchMoreError: 'f',
          nextCursor: 'c',
          inFlightMutationCount: 3,
        ),
      );
    });

    test('keeps what a copy does not replace, and clears what it nulls', () {
      const state = ThreadsState(
        error: 'e',
        fetchMoreError: 'f',
        nextCursor: 'c',
      );

      expect(state.copyWith(), state);
      final cleared = state.copyWith(
        error: () => null,
        fetchMoreError: () => null,
        nextCursor: () => null,
      );
      expect(cleared.error, isNull);
      expect(cleared.fetchMoreError, isNull);
      expect(cleared.nextCursor, isNull);
    });
  });
}
