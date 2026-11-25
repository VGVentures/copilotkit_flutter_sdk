// cspell:ignore realtime
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMemoriesClient extends Mock implements MemoriesClient;

const _tea = Memory(
  id: 'm1',
  kind: MemoryKind.topical,
  scope: MemoryScope.user,
  content: 'Likes tea.',
  sourceThreadIds: ['t1'],
);
const _seats = Memory(
  id: 'm2',
  kind: MemoryKind.episodic,
  scope: MemoryScope.user,
  content: 'Prefers window seats.',
  sourceThreadIds: [],
);
const _coffee = Memory(
  id: 'm3',
  kind: MemoryKind.topical,
  scope: MemoryScope.user,
  content: 'Likes coffee.',
  sourceThreadIds: [],
);
const _draft = NewMemory(content: 'Likes coffee.', kind: MemoryKind.topical);
const _failure = MemoryException(
  code: MemoryErrorCode.mutationFailed,
  message: 'Request failed: 500',
  statusCode: 500,
);
const _unavailable = MemoryUnavailableException(404);

void main() {
  setUpAll(() => registerFallbackValue(_draft));

  group(MemoriesBloc, () {
    late _MockMemoriesClient client;
    late List<Completer<List<Memory>>> pendingLists;

    setUp(() {
      client = _MockMemoriesClient();
      when(() => client.watch(onConnected: any(named: 'onConnected')))
          .thenAnswer((_) => const Stream.empty());
    });

    MemoriesBloc buildBloc() => MemoriesBloc(client: client);

    test('starts available, with nothing loaded', () {
      expect(buildBloc().state, const MemoriesState());
    });

    group(MemoriesRequested, () {
      blocTest<MemoriesBloc, MemoriesState>(
        'loads the memories',
        setUp: () => when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenAnswer((_) async => [_tea, _seats]),
        build: buildBloc,
        act: (bloc) => bloc.add(const MemoriesRequested()),
        expect: () => const [
          MemoriesState(isLoading: true),
          MemoriesState(memories: [_tea, _seats]),
        ],
        verify: (_) => verify(() => client.list()).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'asks for the retired memories too',
        setUp: () => when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenAnswer((_) async => [_tea]),
        build: buildBloc,
        act: (bloc) =>
            bloc.add(const MemoriesRequested(includeInvalidated: true)),
        verify: (_) =>
            verify(() => client.list(includeInvalidated: true)).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'is not an error when the runtime has no memory',
        setUp: () => when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenThrow(_unavailable),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea], recalled: [_tea]),
        act: (bloc) => bloc.add(const MemoriesRequested()),
        expect: () => const [
          MemoriesState(isLoading: true, memories: [_tea], recalled: [_tea]),
          MemoriesState(
            isAvailable: false,
            realtimeStatus: MemoryRealtimeStatus.unavailable,
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'is available again once the runtime has memory',
        setUp: () => when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenAnswer((_) async => [_tea]),
        build: buildBloc,
        seed: () => const MemoriesState(isAvailable: false),
        act: (bloc) => bloc.add(const MemoriesRequested()),
        expect: () => const [
          MemoriesState(isLoading: true, isAvailable: false),
          MemoriesState(memories: [_tea]),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'keeps the memories and reports the error when the list fails',
        setUp: () =>
            when(
              () => client.list(
                includeInvalidated: any(named: 'includeInvalidated'),
              ),
            ).thenThrow(
              const MemoryException(
                code: MemoryErrorCode.listFailed,
                message: 'Request failed: 500',
                statusCode: 500,
              ),
            ),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea]),
        act: (bloc) => bloc.add(const MemoriesRequested()),
        expect: () => const [
          MemoriesState(isLoading: true, memories: [_tea]),
          MemoriesState(
            memories: [_tea],
            realtimeStatus: MemoryRealtimeStatus.unavailable,
            error: MemoryException(
              code: MemoryErrorCode.listFailed,
              message: 'Request failed: 500',
              statusCode: 500,
            ),
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'replaces a load that is still running',
        setUp: () {
          final first = Completer<List<Memory>>();
          var calls = 0;
          when(
            () => client.list(
              includeInvalidated: any(named: 'includeInvalidated'),
            ),
          ).thenAnswer((_) {
            calls++;
            return calls == 1 ? first.future : Future.value([_seats]);
          });
          addTearDown(() => first.complete([_tea]));
        },
        build: buildBloc,
        act: (bloc) => bloc
          ..add(const MemoriesRequested())
          ..add(const MemoriesRequested()),
        expect: () => const [
          MemoriesState(isLoading: true),
          MemoriesState(memories: [_seats]),
        ],
      );
    });

    group('a mutation that finishes while the list loads', () {
      blocTest<MemoriesBloc, MemoriesState>(
        'loads the list again so the stale one does not overwrite it',
        setUp: () {
          final lists = <Completer<List<Memory>>>[];
          when(
            () => client.list(
              includeInvalidated: any(named: 'includeInvalidated'),
            ),
          ).thenAnswer((_) {
            final pending = Completer<List<Memory>>();
            lists.add(pending);
            return pending.future;
          });
          when(() => client.retire(any())).thenAnswer((_) async {});
          pendingLists = lists;
        },
        build: buildBloc,
        act: (bloc) async {
          bloc.add(const MemoriesRequested());
          await pumpEventQueue();
          bloc.add(const MemoryRetired('m1'));
          await pumpEventQueue();
          // The first list was read before the retirement.
          pendingLists.first.complete([_tea, _seats]);
          await pumpEventQueue();
          pendingLists.last.complete([_seats]);
        },
        verify: (bloc) {
          expect(pendingLists, hasLength(2));
          expect(bloc.state.memories, [_seats]);
          expect(bloc.state.isLoading, isFalse);
        },
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'keeps asking for the retired memories when it loads again',
        setUp: () {
          final lists = <Completer<List<Memory>>>[];
          when(
            () => client.list(
              includeInvalidated: any(named: 'includeInvalidated'),
            ),
          ).thenAnswer((_) {
            final pending = Completer<List<Memory>>();
            lists.add(pending);
            return pending.future;
          });
          when(() => client.retire(any())).thenAnswer((_) async {});
          pendingLists = lists;
        },
        build: buildBloc,
        act: (bloc) async {
          bloc.add(const MemoriesRequested(includeInvalidated: true));
          await pumpEventQueue();
          bloc.add(const MemoryRetired('m1'));
          await pumpEventQueue();
          pendingLists.last.complete([_tea]);
        },
        verify: (_) =>
            verify(() => client.list(includeInvalidated: true)).called(2),
      );
    });

    group(MemoriesRecalled, () {
      blocTest<MemoriesBloc, MemoriesState>(
        'puts the recalled memories apart from the list',
        setUp: () => when(
          () => client.recall(
            any(),
            limit: any(named: 'limit'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [_seats]),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea]),
        act: (bloc) => bloc.add(
          const MemoriesRecalled('seats', limit: 3, scope: MemoryScope.user),
        ),
        expect: () => const [
          MemoriesState(memories: [_tea], isRecalling: true),
          MemoriesState(memories: [_tea], recalled: [_seats]),
        ],
        verify: (_) => verify(
          () => client.recall('seats', limit: 3, scope: MemoryScope.user),
        ).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'is not an error when the runtime has no memory',
        setUp: () => when(
          () => client.recall(
            any(),
            limit: any(named: 'limit'),
            scope: any(named: 'scope'),
          ),
        ).thenThrow(_unavailable),
        build: buildBloc,
        act: (bloc) => bloc.add(const MemoriesRecalled('seats')),
        expect: () => const [
          MemoriesState(isRecalling: true),
          MemoriesState(
            isAvailable: false,
            realtimeStatus: MemoryRealtimeStatus.unavailable,
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'reports a query the runtime rejects',
        setUp: () => when(
          () => client.recall(
            any(),
            limit: any(named: 'limit'),
            scope: any(named: 'scope'),
          ),
        ).thenThrow(const MemoryValidationException('query is blank.')),
        build: buildBloc,
        act: (bloc) => bloc.add(const MemoriesRecalled(' ')),
        expect: () => const [
          MemoriesState(isRecalling: true),
          MemoriesState(error: MemoryValidationException('query is blank.')),
        ],
      );
    });

    group(MemorySaved, () {
      blocTest<MemoriesBloc, MemoriesState>(
        'puts the new memory first',
        setUp: () => when(
          () => client.save(any()),
        ).thenAnswer((_) async => const MemoryMutationOutcome(memory: _coffee)),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea]),
        act: (bloc) => bloc.add(const MemorySaved(_draft)),
        expect: () => const [
          MemoriesState(memories: [_tea], inFlightMutationCount: 1),
          MemoriesState(
            memories: [_coffee, _tea],
            lastOutcome: MemoryMutationOutcome(memory: _coffee),
          ),
        ],
        verify: (_) => verify(() => client.save(_draft)).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'reports a near-duplicate as absorbed, without adding it twice',
        setUp: () => when(() => client.save(any())).thenAnswer(
          (_) async =>
              const MemoryMutationOutcome(memory: _tea, isAbsorbed: true),
        ),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_seats, _tea]),
        act: (bloc) => bloc.add(const MemorySaved(_draft)),
        expect: () => const [
          MemoriesState(memories: [_seats, _tea], inFlightMutationCount: 1),
          MemoriesState(
            memories: [_seats, _tea],
            lastOutcome: MemoryMutationOutcome(memory: _tea, isAbsorbed: true),
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'reports the failure and keeps the list',
        setUp: () => when(() => client.save(any())).thenThrow(_failure),
        build: buildBloc,
        seed: () => const MemoriesState(
          memories: [_tea],
          lastOutcome: MemoryMutationOutcome(memory: _tea),
        ),
        act: (bloc) => bloc.add(const MemorySaved(_draft)),
        expect: () => const [
          MemoriesState(
            memories: [_tea],
            inFlightMutationCount: 1,
            lastOutcome: MemoryMutationOutcome(memory: _tea),
          ),
          MemoriesState(memories: [_tea], error: _failure),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'reports a memory that breaks a limit',
        setUp: () => when(() => client.save(any()))
            .thenThrow(const MemoryValidationException('content is too long.')),
        build: buildBloc,
        act: (bloc) => bloc.add(const MemorySaved(_draft)),
        expect: () => const [
          MemoriesState(inFlightMutationCount: 1),
          MemoriesState(
            error: MemoryValidationException('content is too long.'),
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'is not an error when the runtime has no memory',
        setUp: () =>
            when(() => client.save(any()))
                .thenThrow(const MemoryUnavailableException(403)),
        build: buildBloc,
        act: (bloc) => bloc.add(const MemorySaved(_draft)),
        expect: () => const [
          MemoriesState(inFlightMutationCount: 1),
          MemoriesState(
            isAvailable: false,
            realtimeStatus: MemoryRealtimeStatus.unavailable,
          ),
        ],
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'counts the saves that run at the same time',
        setUp: () {
          final first = Completer<MemoryMutationOutcome>();
          var calls = 0;
          when(() => client.save(any())).thenAnswer((_) {
            calls++;
            return calls == 1
                ? first.future
                : Future.value(const MemoryMutationOutcome(memory: _seats));
          });
          Future<void>.delayed(
            const Duration(milliseconds: 20),
            () => first.complete(const MemoryMutationOutcome(memory: _coffee)),
          );
        },
        build: buildBloc,
        act: (bloc) => bloc
          ..add(const MemorySaved(_draft))
          ..add(const MemorySaved(_draft)),
        wait: const Duration(milliseconds: 50),
        expect: () => [
          const MemoriesState(inFlightMutationCount: 1),
          const MemoriesState(inFlightMutationCount: 2),
          const MemoriesState(
            memories: [_seats],
            inFlightMutationCount: 1,
            lastOutcome: MemoryMutationOutcome(memory: _seats),
          ),
          const MemoriesState(
            memories: [_coffee, _seats],
            lastOutcome: MemoryMutationOutcome(memory: _coffee),
          ),
        ],
      );
    });

    group(MemorySuperseded, () {
      const replacement = Memory(
        id: 'm9',
        kind: MemoryKind.topical,
        scope: MemoryScope.user,
        content: 'Likes green tea.',
        sourceThreadIds: [],
      );
      const outcome = MemoryMutationOutcome(
        memory: replacement,
        retiredId: 'm1',
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'swaps the retired memory for the one with the new id',
        setUp: () =>
            when(() => client.supersede(any(), any()))
                .thenAnswer((_) async => outcome),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_seats, _tea]),
        act: (bloc) => bloc.add(const MemorySuperseded('m1', _draft)),
        expect: () => const [
          MemoriesState(memories: [_seats, _tea], inFlightMutationCount: 1),
          MemoriesState(memories: [replacement, _seats], lastOutcome: outcome),
        ],
        verify: (_) => verify(() => client.supersede('m1', _draft)).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'removes the retired memory from the recalled ones too',
        setUp: () =>
            when(() => client.supersede(any(), any()))
                .thenAnswer((_) async => outcome),
        build: buildBloc,
        seed: () =>
            const MemoriesState(memories: [_tea], recalled: [_tea, _seats]),
        act: (bloc) => bloc.add(const MemorySuperseded('m1', _draft)),
        verify: (bloc) {
          expect(bloc.state.recalled, [_seats]);
          expect(bloc.state.memories, [replacement]);
        },
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'marks the retired memory instead of removing it in a full list',
        setUp: () =>
            when(() => client.supersede(any(), any()))
                .thenAnswer((_) async => outcome),
        build: buildBloc,
        seed: () =>
            const MemoriesState(memories: [_tea], includeInvalidated: true),
        act: (bloc) => bloc.add(const MemorySuperseded('m1', _draft)),
        verify: (bloc) {
          expect(bloc.state.memories.map((m) => m.id), ['m9', 'm1']);
          expect(bloc.state.memories.last.invalidatedAt, isNotNull);
        },
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'reports the failure and keeps the list',
        setUp: () =>
            when(() => client.supersede(any(), any())).thenThrow(_failure),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea]),
        act: (bloc) => bloc.add(const MemorySuperseded('m1', _draft)),
        expect: () => const [
          MemoriesState(memories: [_tea], inFlightMutationCount: 1),
          MemoriesState(memories: [_tea], error: _failure),
        ],
      );
    });

    group(MemoryRetired, () {
      blocTest<MemoriesBloc, MemoriesState>(
        'removes the memory from the list and the recalled ones',
        setUp: () => when(() => client.retire(any())).thenAnswer((_) async {}),
        build: buildBloc,
        seed: () => const MemoriesState(
          memories: [_seats, _tea],
          recalled: [_tea],
          lastOutcome: MemoryMutationOutcome(memory: _tea),
        ),
        act: (bloc) => bloc.add(const MemoryRetired('m1')),
        expect: () => const [
          MemoriesState(
            memories: [_seats, _tea],
            recalled: [_tea],
            inFlightMutationCount: 1,
            lastOutcome: MemoryMutationOutcome(memory: _tea),
          ),
          MemoriesState(memories: [_seats]),
        ],
        verify: (_) => verify(() => client.retire('m1')).called(1),
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'marks the memory retired in a list that includes retired ones',
        setUp: () => when(() => client.retire(any())).thenAnswer((_) async {}),
        build: buildBloc,
        seed: () => const MemoriesState(
          memories: [_seats, _tea],
          includeInvalidated: true,
        ),
        act: (bloc) => bloc.add(const MemoryRetired('m1')),
        verify: (bloc) {
          expect(bloc.state.memories.map((m) => m.id), ['m2', 'm1']);
          expect(bloc.state.memories.first.invalidatedAt, isNull);
          final retired = bloc.state.memories.last;
          expect(retired.invalidatedAt, isNotNull);
          expect(retired.content, _tea.content);
        },
      );

      blocTest<MemoriesBloc, MemoriesState>(
        'keeps the memory and reports the failure',
        setUp: () => when(() => client.retire(any())).thenThrow(_failure),
        build: buildBloc,
        seed: () => const MemoriesState(memories: [_tea]),
        act: (bloc) => bloc.add(const MemoryRetired('m1')),
        expect: () => const [
          MemoriesState(memories: [_tea], inFlightMutationCount: 1),
          MemoriesState(memories: [_tea], error: _failure),
        ],
      );
    });

    group('live memories', () {
      late StreamController<MemoryMetadataEvent> live;
      late void Function() connect;
      final at = DateTime.utc(2026, 11, 25);

      MemoryMetadataEvent change(
        MemoryMetadataOperation operation,
        String id, [
        Memory? memory,
      ]) => MemoryMetadataEvent(
        operation: operation,
        memoryId: id,
        occurredAt: at,
        memory: memory,
      );

      setUp(() {
        live = StreamController<MemoryMetadataEvent>();
        when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenAnswer((_) async => [_tea, _seats]);
        when(
          () => client.watch(onConnected: any(named: 'onConnected')),
        ).thenAnswer((invocation) {
          connect = invocation.namedArguments[#onConnected]! as void Function();
          return live.stream;
        });
      });

      // A stream nobody listened to never reports that it closed.
      tearDown(() => unawaited(live.close()));

      Future<MemoriesBloc> following({bool includeInvalidated = false}) async {
        final bloc = buildBloc()
          ..add(MemoriesRequested(includeInvalidated: includeInvalidated));
        await pumpEventQueue();
        return bloc;
      }

      Future<List<Memory>> after(
        MemoriesBloc bloc,
        List<MemoryMetadataEvent> events,
      ) async {
        events.forEach(live.add);
        await pumpEventQueue();
        return bloc.state.memories;
      }

      test('is connecting until the channel joins, then connected', () async {
        final bloc = await following();

        expect(bloc.state.realtimeStatus, MemoryRealtimeStatus.connecting);
        connect();
        await pumpEventQueue();
        expect(bloc.state.realtimeStatus, MemoryRealtimeStatus.connected);
        await bloc.close();
        expect(live.hasListener, isFalse);
      });

      test('adds a created memory first, once', () async {
        final bloc = await following();
        final event = change(MemoryMetadataOperation.created, 'm3', _coffee);

        expect(await after(bloc, [event, event]), [_coffee, _tea, _seats]);
        await bloc.close();
      });

      test('puts an updated memory in place', () async {
        final bloc = await following();
        const warmer = Memory(
          id: 'm2',
          kind: MemoryKind.episodic,
          scope: MemoryScope.user,
          content: 'Prefers aisle seats.',
          sourceThreadIds: [],
        );

        expect(
          await after(bloc, [
            change(MemoryMetadataOperation.updated, 'm2', warmer),
          ]),
          [_tea, warmer],
        );
        await bloc.close();
      });

      test('removes an invalidated memory, from the recall too', () async {
        when(
          () => client.recall(
            any(),
            limit: any(named: 'limit'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [_tea]);
        final bloc = await following()
          ..add(const MemoriesRecalled('tea'));
        await pumpEventQueue();

        expect(
          await after(bloc, [
            change(MemoryMetadataOperation.invalidated, 'm1'),
          ]),
          [_seats],
        );
        expect(bloc.state.recalled, isEmpty);
        await bloc.close();
      });

      test('marks an invalidated memory retired when retired ones are '
          'listed', () async {
        final bloc = await following(includeInvalidated: true);

        final memories = await after(bloc, [
          change(MemoryMetadataOperation.invalidated, 'm1'),
        ]);

        expect(memories.map((memory) => memory.isRetired), [true, false]);
        await bloc.close();
      });

      test('does not bring back a memory after it was invalidated', () async {
        final bloc = await following();

        expect(
          await after(bloc, [
            change(MemoryMetadataOperation.invalidated, 'm1'),
            // A stale copy the service repeated.
            change(MemoryMetadataOperation.created, 'm1', _tea),
          ]),
          [_seats],
        );
        await bloc.close();
      });

      test('does not bring back a memory it retired itself', () async {
        when(() => client.retire('m1')).thenAnswer((_) async {});
        final bloc = await following()
          ..add(const MemoryRetired('m1'));
        await pumpEventQueue();

        expect(
          await after(bloc, [
            change(MemoryMetadataOperation.created, 'm1', _tea),
          ]),
          [_seats],
        );
        await bloc.close();
      });

      test('ignores an event without a memory', () async {
        final bloc = await following();

        expect(
          await after(bloc, [change(MemoryMetadataOperation.updated, 'm1')]),
          [_tea, _seats],
        );
        await bloc.close();
      });

      test('is unavailable when the channel fails for good, and keeps the '
          'list', () async {
        final bloc = await following();
        connect();
        await pumpEventQueue();

        live.addError(
          const MemoryException(
            code: MemoryErrorCode.realtimeUnavailable,
            message: 'gave up',
          ),
        );
        await live.close();
        await pumpEventQueue();

        expect(bloc.state.realtimeStatus, MemoryRealtimeStatus.unavailable);
        expect(bloc.state.memories, [_tea, _seats]);
        expect(bloc.state.error, isNull);
        await bloc.close();
      });

      test('ignores the join of a list it replaced', () async {
        final bloc = await following();
        final stale = connect;
        live = StreamController<MemoryMetadataEvent>();

        bloc.add(const MemoriesRequested());
        await pumpEventQueue();
        stale();
        await pumpEventQueue();

        expect(bloc.state.realtimeStatus, MemoryRealtimeStatus.connecting);
        await bloc.close();
      });

      test('is unavailable when the runtime has no memory', () async {
        when(
          () =>
              client.list(includeInvalidated: any(named: 'includeInvalidated')),
        ).thenThrow(_unavailable);
        final bloc = await following();

        expect(bloc.state.realtimeStatus, MemoryRealtimeStatus.unavailable);
        verifyNever(() => client.watch(onConnected: any(named: 'onConnected')));
        await bloc.close();
      });
    });
  });
}
