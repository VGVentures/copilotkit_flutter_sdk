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

    setUp(() => client = _MockMemoriesClient());

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
          MemoriesState(isAvailable: false),
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
        expect: () => const [MemoriesState(isAvailable: false)],
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
          MemoriesState(isAvailable: false),
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
  });
}
