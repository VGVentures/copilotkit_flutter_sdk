// cspell:ignore realtime
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockThreadsClient extends Mock implements ThreadsClient;

ThreadRecord _thread(String id, {bool archived = false, String? name}) =>
    ThreadRecord(
      id: id,
      agentId: 'default',
      archived: archived,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      name: name,
    );

ThreadsException _failure(ThreadsErrorCode code) =>
    ThreadsException(code: code, message: 'boom', statusCode: 500);

void main() {
  group(ThreadsBloc, () {
    late _MockCopilotKitClient client;
    late _MockThreadsClient threads;
    late Completer<void> pendingDelete;
    late Completer<ThreadPage> pendingPage;

    setUp(() {
      client = _MockCopilotKitClient();
      threads = _MockThreadsClient();
      when(() => client.threads).thenReturn(threads);
      when(client.threadEndpoints).thenAnswer(
        (_) async => const ThreadEndpoints(list: true, mutations: true),
      );
    });

    ThreadsBloc build({bool includeArchived = false, int? limit}) =>
        ThreadsBloc(
          client: client,
          agentId: 'default',
          includeArchived: includeArchived,
          limit: limit,
        );

    void stubList(ThreadPage page) => when(
      () => threads.list(
        agentId: any(named: 'agentId'),
        includeArchived: any(named: 'includeArchived'),
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer((_) async => page);

    void stubListThrows(Object error) => when(
      () => threads.list(
        agentId: any(named: 'agentId'),
        includeArchived: any(named: 'includeArchived'),
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
      ),
    ).thenThrow(error);

    final a = _thread('a', name: 'First');
    final b = _thread('b');
    final c = _thread('c');
    ThreadsState loaded({
      List<ThreadRecord>? threads,
      bool canMutate = true,
      String? nextCursor,
    }) => ThreadsState(
      threads: threads ?? [a, b, c],
      canMutate: canMutate,
      nextCursor: nextCursor,
    );

    test('starts with nothing loaded', () {
      expect(build().state, const ThreadsState());
    });

    group('ThreadsRequested', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'loads the first page',
        setUp: () => stubList(ThreadPage(threads: [a, b], nextCursor: 'c1')),
        build: build,
        act: (bloc) => bloc.add(const ThreadsRequested()),
        expect: () => [
          const ThreadsState(isLoading: true),
          const ThreadsState(isLoading: true, canMutate: true),
          ThreadsState(threads: [a, b], canMutate: true, nextCursor: 'c1'),
        ],
        verify: (_) => verify(() => threads.list(agentId: 'default')).called(1),
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'asks for archived threads and a page size when told to',
        setUp: () => stubList(const ThreadPage(threads: [])),
        build: () => build(includeArchived: true, limit: 20),
        act: (bloc) => bloc.add(const ThreadsRequested()),
        verify: (_) => verify(
          () => threads.list(
            agentId: 'default',
            includeArchived: true,
            limit: 20,
          ),
        ).called(1),
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'reads a runtime that cannot change threads',
        setUp: () {
          when(client.threadEndpoints)
              .thenAnswer((_) async => const ThreadEndpoints(list: true));
          stubList(ThreadPage(threads: [a]));
        },
        build: build,
        act: (bloc) => bloc.add(const ThreadsRequested()),
        expect: () => [
          const ThreadsState(isLoading: true),
          ThreadsState(threads: [a]),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'is unavailable when the runtime has no thread routes',
        setUp: () =>
            when(client.threadEndpoints)
                .thenAnswer((_) async => const ThreadEndpoints()),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadsRequested()),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isLoading, 'isLoading', true),
          isA<ThreadsState>().having((s) => s.canMutate, 'canMutate', false),
          const ThreadsState(isAvailable: false),
        ],
        verify: (_) =>
            verifyNever(() => threads.list(agentId: any(named: 'agentId'))),
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'keeps the error when the list fails',
        setUp: () => stubListThrows(_failure(ThreadsErrorCode.listFailed)),
        build: build,
        act: (bloc) => bloc.add(const ThreadsRequested()),
        expect: () => [
          const ThreadsState(isLoading: true),
          const ThreadsState(isLoading: true, canMutate: true),
          ThreadsState(
            canMutate: true,
            error: _failure(ThreadsErrorCode.listFailed),
          ),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'clears an earlier error when it loads again',
        setUp: () => stubList(ThreadPage(threads: [a])),
        build: build,
        seed: () => ThreadsState(
          error: _failure(ThreadsErrorCode.listFailed),
          fetchMoreError: _failure(ThreadsErrorCode.listFailed),
        ),
        act: (bloc) => bloc.add(const ThreadsRequested()),
        expect: () => [
          const ThreadsState(isLoading: true),
          const ThreadsState(isLoading: true, canMutate: true),
          ThreadsState(threads: [a], canMutate: true),
        ],
      );
    });

    group('ThreadsNextPageRequested', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'adds the next page without repeating a thread',
        setUp: () => stubList(ThreadPage(threads: [b, c])),
        build: build,
        seed: () => loaded(threads: [a, b], nextCursor: 'c1'),
        act: (bloc) => bloc.add(const ThreadsNextPageRequested()),
        expect: () => [
          ThreadsState(
            threads: [a, b],
            isFetchingNextPage: true,
            canMutate: true,
            nextCursor: 'c1',
          ),
          ThreadsState(threads: [a, b, c], canMutate: true),
        ],
        verify: (_) =>
            verify(() => threads.list(agentId: 'default', cursor: 'c1'))
                .called(1),
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'does nothing on the last page',
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadsNextPageRequested()),
        expect: () => <ThreadsState>[],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'keeps the threads and sets fetchMoreError when a page fails',
        setUp: () => stubListThrows(_failure(ThreadsErrorCode.listFailed)),
        build: build,
        seed: () => loaded(threads: [a], nextCursor: 'c1'),
        act: (bloc) => bloc.add(const ThreadsNextPageRequested()),
        expect: () => [
          isA<ThreadsState>().having(
            (s) => s.isFetchingNextPage,
            'isFetchingNextPage',
            true,
          ),
          ThreadsState(
            threads: [a],
            canMutate: true,
            nextCursor: 'c1',
            fetchMoreError: _failure(ThreadsErrorCode.listFailed),
          ),
        ],
      );
    });

    group('ThreadsNextPageRequested during a refresh', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'waits for the first page that is loading',
        build: build,
        seed: () => loaded(nextCursor: 'c1').copyWith(isLoading: true),
        act: (bloc) => bloc.add(const ThreadsNextPageRequested()),
        expect: () => <ThreadsState>[],
        verify: (_) => verifyNever(
          () => threads.list(
            agentId: any(named: 'agentId'),
            includeArchived: any(named: 'includeArchived'),
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
          ),
        ),
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'drops a page that continues a list a refresh has replaced',
        setUp: () {
          stubList(ThreadPage(threads: [a, b], nextCursor: 'c2'));
          final pending = Completer<ThreadPage>();
          when(() => threads.list(agentId: 'default', cursor: 'c1'))
              .thenAnswer((_) => pending.future);
          pendingPage = pending;
        },
        build: build,
        seed: () => loaded(threads: [a], nextCursor: 'c1'),
        act: (bloc) async {
          bloc.add(const ThreadsNextPageRequested());
          await pumpEventQueue();
          bloc.add(const ThreadsRequested());
          await pumpEventQueue();
          pendingPage.complete(ThreadPage(threads: [c], nextCursor: 'c3'));
        },
        verify: (bloc) {
          expect(bloc.state.threads, [a, b]);
          expect(bloc.state.nextCursor, 'c2');
          expect(bloc.state.isFetchingNextPage, isFalse);
        },
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'ignores the failure of a page a refresh has replaced',
        setUp: () {
          stubList(ThreadPage(threads: [a, b], nextCursor: 'c2'));
          final pending = Completer<ThreadPage>();
          when(() => threads.list(agentId: 'default', cursor: 'c1'))
              .thenAnswer((_) => pending.future);
          pendingPage = pending;
        },
        build: build,
        seed: () => loaded(threads: [a], nextCursor: 'c1'),
        act: (bloc) async {
          bloc.add(const ThreadsNextPageRequested());
          await pumpEventQueue();
          bloc.add(const ThreadsRequested());
          await pumpEventQueue();
          pendingPage.completeError(_failure(ThreadsErrorCode.listFailed));
        },
        verify: (bloc) {
          expect(bloc.state.threads, [a, b]);
          expect(bloc.state.fetchMoreError, isNull);
          expect(bloc.state.isFetchingNextPage, isFalse);
        },
      );
    });

    group('ThreadRenamed', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'puts the renamed thread the runtime answered with in the list',
        setUp: () => when(
          () =>
              threads.rename(agentId: 'default', threadId: 'b', name: 'Second'),
        ).thenAnswer((_) async => b.copyWith(name: 'Second')),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadRenamed('b', 'Second')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          loaded(
            threads: [
              a,
              b.copyWith(name: 'Second'),
              c,
            ],
          ),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'leaves the list alone when the runtime rejects it',
        setUp: () => when(
          () => threads.rename(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
            name: any(named: 'name'),
          ),
        ).thenThrow(_failure(ThreadsErrorCode.mutationFailed)),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadRenamed('b', 'Second')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          ThreadsState(
            threads: [a, b, c],
            canMutate: true,
            error: _failure(ThreadsErrorCode.mutationFailed),
          ),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'is refused when the runtime cannot change threads',
        build: build,
        seed: () => loaded(canMutate: false),
        act: (bloc) => bloc.add(const ThreadRenamed('b', 'Second')),
        expect: () => [
          isA<ThreadsState>().having(
            (s) => s.error,
            'error',
            isA<UnsupportedError>(),
          ),
        ],
        verify: (_) => verifyNever(
          () => threads.rename(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
            name: any(named: 'name'),
          ),
        ),
      );
    });

    group('ThreadArchived', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'removes the thread from the default list',
        setUp: () =>
            when(() => threads.archive(agentId: 'default', threadId: 'b'))
                .thenAnswer((_) async {}),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadArchived('b')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          loaded(threads: [a, c]),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'marks the thread as archived when archived threads are listed',
        setUp: () =>
            when(() => threads.archive(agentId: 'default', threadId: 'b'))
                .thenAnswer((_) async {}),
        build: () => build(includeArchived: true),
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadArchived('b')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          loaded(threads: [a, b.copyWith(archived: true), c]),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'keeps the thread when the runtime rejects it',
        setUp: () => when(
          () => threads.archive(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
          ),
        ).thenThrow(_failure(ThreadsErrorCode.mutationFailed)),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadArchived('b')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          isA<ThreadsState>()
              .having((s) => s.threads, 'threads', [a, b, c])
              .having((s) => s.error, 'error', isA<ThreadsException>()),
        ],
      );
    });

    group('ThreadUnarchived', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'puts the thread the runtime answered with in the list',
        setUp: () =>
            when(() => threads.unarchive(agentId: 'default', threadId: 'b'))
                .thenAnswer((_) async => b),
        build: () => build(includeArchived: true),
        seed: () => loaded(threads: [a, b.copyWith(archived: true), c]),
        act: (bloc) => bloc.add(const ThreadUnarchived('b')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          loaded(),
        ],
      );
    });

    group('ThreadDeleted', () {
      blocTest<ThreadsBloc, ThreadsState>(
        'removes the thread at once and keeps it removed',
        setUp: () =>
            when(() => threads.delete(agentId: 'default', threadId: 'b'))
                .thenAnswer((_) async {}),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadDeleted('b')),
        expect: () => [
          const ThreadsState(
            canMutate: true,
            inFlightMutationCount: 1,
          ).copyWith(threads: [a, c]),
          loaded(threads: [a, c]),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'puts the thread back in its place when the runtime rejects it',
        setUp: () => when(
          () => threads.delete(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
          ),
        ).thenThrow(_failure(ThreadsErrorCode.mutationFailed)),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadDeleted('b')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.threads, 'threads', [a, c]),
          ThreadsState(
            threads: [a, b, c],
            canMutate: true,
            error: _failure(ThreadsErrorCode.mutationFailed),
          ),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'puts a thread back at the end when the list got shorter meanwhile',
        setUp: () {
          final pending = Completer<void>();
          when(() => threads.delete(agentId: 'default', threadId: 'c'))
              .thenAnswer((_) => pending.future);
          when(() => threads.delete(agentId: 'default', threadId: 'b'))
              .thenAnswer((_) async {});
          pendingDelete = pending;
        },
        build: build,
        seed: loaded,
        act: (bloc) async {
          bloc.add(const ThreadDeleted('c'));
          await pumpEventQueue();
          bloc.add(const ThreadDeleted('b'));
          await pumpEventQueue();
          pendingDelete.completeError(
            _failure(ThreadsErrorCode.mutationFailed),
          );
        },
        verify: (bloc) {
          // c was at index 2, but only a is left, so it goes after a.
          expect(bloc.state.threads, [a, c]);
          expect(bloc.state.error, isA<ThreadsException>());
          expect(bloc.state.isMutating, isFalse);
        },
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'does not list a thread twice when a refresh brought it back first',
        setUp: () {
          stubList(ThreadPage(threads: [a, b, c]));
          pendingDelete = Completer<void>();
          when(() => threads.delete(agentId: 'default', threadId: 'b'))
              .thenAnswer((_) => pendingDelete.future);
        },
        build: build,
        seed: loaded,
        act: (bloc) async {
          bloc.add(const ThreadDeleted('b'));
          await pumpEventQueue();
          bloc.add(const ThreadsRequested());
          await pumpEventQueue();
          pendingDelete.completeError(
            _failure(ThreadsErrorCode.mutationFailed),
          );
        },
        verify: (bloc) {
          expect(bloc.state.threads, [a, b, c]);
          expect(bloc.state.error, isA<ThreadsException>());
        },
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'removes a thread a refresh brought back when its delete succeeds',
        setUp: () {
          stubList(ThreadPage(threads: [a, b, c]));
          pendingDelete = Completer<void>();
          when(() => threads.delete(agentId: 'default', threadId: 'b'))
              .thenAnswer((_) => pendingDelete.future);
        },
        build: build,
        seed: loaded,
        act: (bloc) async {
          bloc.add(const ThreadDeleted('b'));
          await pumpEventQueue();
          bloc.add(const ThreadsRequested());
          await pumpEventQueue();
          pendingDelete.complete();
        },
        verify: (bloc) {
          expect(bloc.state.threads, [a, c]);
          expect(bloc.state.isMutating, isFalse);
        },
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'sends a delete for a thread that is not in the list',
        setUp: () => when(
          () => threads.delete(
            agentId: any(named: 'agentId'),
            threadId: any(named: 'threadId'),
          ),
        ).thenThrow(_failure(ThreadsErrorCode.mutationFailed)),
        build: build,
        seed: loaded,
        act: (bloc) => bloc.add(const ThreadDeleted('unknown')),
        expect: () => [
          isA<ThreadsState>().having((s) => s.isMutating, 'isMutating', true),
          isA<ThreadsState>()
              .having((s) => s.threads, 'threads', [a, b, c])
              .having((s) => s.error, 'error', isA<ThreadsException>()),
        ],
      );

      blocTest<ThreadsBloc, ThreadsState>(
        'is refused when the runtime cannot change threads',
        build: build,
        seed: () => loaded(canMutate: false),
        act: (bloc) => bloc.add(const ThreadDeleted('b')),
        expect: () => [
          isA<ThreadsState>().having(
            (s) => s.error,
            'error',
            isA<UnsupportedError>(),
          ),
        ],
        verify: (bloc) {
          expect(bloc.state.threads, [a, b, c]);
          verifyNever(
            () => threads.delete(
              agentId: any(named: 'agentId'),
              threadId: any(named: 'threadId'),
            ),
          );
        },
      );
    });

    group('live thread metadata', () {
      late StreamController<ThreadMetadataEvent> live;
      final newer = DateTime.utc(2027);

      ThreadRecord thread(
        String id, {
        String agentId = 'default',
        bool archived = false,
        String? name,
      }) => ThreadRecord(
        id: id,
        agentId: agentId,
        archived: archived,
        createdAt: DateTime.utc(2026),
        updatedAt: newer,
        name: name,
      );

      ThreadMetadataEvent change(
        ThreadMetadataOperation operation,
        String threadId, [
        ThreadRecord? thread,
      ]) => ThreadMetadataEvent(
        operation: operation,
        threadId: threadId,
        occurredAt: newer,
        thread: thread,
      );

      setUp(() {
        live = StreamController<ThreadMetadataEvent>();
        when(client.threadEndpoints).thenAnswer(
          (_) async => const ThreadEndpoints(
            list: true,
            mutations: true,
            realtimeMetadata: true,
          ),
        );
        stubList(ThreadPage(threads: [a, b, c], joinCode: 'code-1'));
        when(() => client.watchThreads(any())).thenAnswer((_) => live.stream);
      });

      // A stream nobody listened to never reports that it closed.
      tearDown(() => unawaited(live.close()));

      /// A bloc that loaded [a], [b] and [c] and follows the channel.
      Future<ThreadsBloc> following({bool includeArchived = false}) async {
        final bloc = build(includeArchived: includeArchived)
          ..add(const ThreadsRequested());
        await pumpEventQueue();
        return bloc;
      }

      Future<List<ThreadRecord>> after(
        ThreadsBloc bloc,
        List<ThreadMetadataEvent> events,
      ) async {
        events.forEach(live.add);
        await pumpEventQueue();
        return bloc.state.threads;
      }

      test('follows the channel of the list it loaded', () async {
        final bloc = await following();

        verify(() => client.watchThreads('code-1')).called(1);
        expect(live.hasListener, isTrue);
        await bloc.close();
        expect(live.hasListener, isFalse);
      });

      test('does not follow without real-time thread metadata', () async {
        when(client.threadEndpoints).thenAnswer(
          (_) async => const ThreadEndpoints(list: true, mutations: true),
        );
        final bloc = await following();

        verifyNever(() => client.watchThreads(any()));
        await bloc.close();
      });

      test('does not follow without a join code', () async {
        stubList(ThreadPage(threads: [a, b, c]));
        final bloc = await following();

        verifyNever(() => client.watchThreads(any()));
        await bloc.close();
      });

      test('adds a created thread first', () async {
        final bloc = await following();
        final d = thread('d');

        expect(
          await after(bloc, [change(ThreadMetadataOperation.created, 'd', d)]),
          [d, a, b, c],
        );
        await bloc.close();
      });

      test('puts a renamed thread in place, and first', () async {
        final bloc = await following();
        final renamed = thread('c', name: 'Renamed');
        final event = change(ThreadMetadataOperation.renamed, 'c', renamed);

        expect(await after(bloc, [event]), [renamed, a, b]);
        // The service may push an event twice.
        expect(await after(bloc, [event]), [renamed, a, b]);
        await bloc.close();
      });

      test('removes a deleted thread', () async {
        final bloc = await following();

        expect(
          await after(bloc, [change(ThreadMetadataOperation.deleted, 'b')]),
          [a, c],
        );
        await bloc.close();
      });

      test('removes an archived thread from a list without them', () async {
        final bloc = await following();
        final archived = thread('b', archived: true);

        expect(
          await after(bloc, [
            change(ThreadMetadataOperation.archived, 'b', archived),
          ]),
          [a, c],
        );
        await bloc.close();
      });

      test('keeps an archived thread in a list with them', () async {
        final bloc = await following(includeArchived: true);
        final archived = thread('b', archived: true);

        expect(
          await after(bloc, [
            change(ThreadMetadataOperation.archived, 'b', archived),
          ]),
          [archived, a, c],
        );
        await bloc.close();
      });

      test('ignores threads of other agents and events without one', () async {
        final bloc = await following();

        expect(
          await after(bloc, [
            change(
              ThreadMetadataOperation.created,
              'x',
              thread('x', agentId: 'other'),
            ),
            change(ThreadMetadataOperation.updated, 'a'),
          ]),
          [a, b, c],
        );
        await bloc.close();
      });

      test('does not bring back a thread while it is deleted', () async {
        final pending = Completer<void>();
        when(() => threads.delete(agentId: 'default', threadId: 'b'))
            .thenAnswer((_) => pending.future);
        final bloc = await following()
          ..add(const ThreadDeleted('b'));
        await pumpEventQueue();

        expect(
          await after(bloc, [
            change(ThreadMetadataOperation.renamed, 'b', thread('b')),
          ]),
          [a, c],
        );
        pending.complete();
        await pumpEventQueue();
        expect(bloc.state.threads, [a, c]);
        await bloc.close();
      });

      test('keeps the list when the channel fails for good', () async {
        final bloc = await following();

        live.addError(
          const ThreadsException(
            code: ThreadsErrorCode.realtimeUnavailable,
            message: 'gave up',
          ),
        );
        await live.close();
        await pumpEventQueue();

        expect(bloc.state.threads, [a, b, c]);
        expect(bloc.state.error, isNull);
        await bloc.close();
      });

      test('stops following the old list on a new request', () async {
        final first = live;
        final bloc = await following();
        live = StreamController<ThreadMetadataEvent>();

        bloc.add(const ThreadsRequested());
        await pumpEventQueue();

        expect(first.hasListener, isFalse);
        expect(live.hasListener, isTrue);
        await first.close();
        await bloc.close();
      });
    });
  });
}
