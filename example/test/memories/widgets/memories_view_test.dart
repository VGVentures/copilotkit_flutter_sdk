import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/memories_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMemoriesBloc extends MockBloc<MemoriesEvent, MemoriesState>
    implements MemoriesBloc;

const _tea = Memory(
  id: 'a',
  kind: MemoryKind.topical,
  scope: MemoryScope.user,
  content: 'Likes tea',
  sourceThreadIds: [],
);

Memory _memory(String id, String content) => Memory(
  id: id,
  kind: MemoryKind.topical,
  scope: MemoryScope.user,
  content: content,
  sourceThreadIds: const [],
);

void main() {
  setUpAll(() => registerFallbackValue(const MemoriesRequested()));

  group(MemoriesView, () {
    late _MockMemoriesBloc bloc;

    setUp(() => bloc = _MockMemoriesBloc());

    Future<void> pump(WidgetTester tester, MemoriesState state) {
      when(() => bloc.state).thenReturn(state);
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<MemoriesBloc>.value(
            value: bloc,
            child: const MemoriesView(),
          ),
        ),
      );
    }

    testWidgets('says when the runtime keeps no memories', (tester) async {
      await pump(tester, const MemoriesState(isAvailable: false));

      expect(find.byKey(const Key('memories_unavailable')), findsOneWidget);
    });

    testWidgets('shows a spinner while the first load runs', (tester) async {
      await pump(tester, const MemoriesState(isLoading: true));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('says when nothing is remembered', (tester) async {
      await pump(tester, const MemoriesState());

      expect(find.text('Nothing remembered yet.'), findsOneWidget);
    });

    testWidgets('lists the memories', (tester) async {
      await pump(tester, MemoriesState(memories: [_memory('a', 'Likes tea')]));

      expect(find.text('Likes tea'), findsOneWidget);
      expect(find.text('topical · user'), findsOneWidget);
      expect(find.text('Search results'), findsNothing);
    });

    testWidgets('lists search results apart from the memories', (tester) async {
      await pump(
        tester,
        MemoriesState(
          memories: [_memory('a', 'Likes tea')],
          recalled: [_memory('b', 'Drinks coffee')],
        ),
      );

      expect(find.text('Search results'), findsOneWidget);
      expect(find.text('Drinks coffee'), findsOneWidget);
    });

    testWidgets('says when a memory was already known', (tester) async {
      await pump(
        tester,
        MemoriesState(
          lastOutcome: MemoryMutationOutcome(
            memory: _memory('a', 'Likes tea'),
            isAbsorbed: true,
          ),
        ),
      );

      expect(find.byKey(const Key('memories_absorbed')), findsOneWidget);
    });

    testWidgets('shows a notice when something failed', (tester) async {
      await pump(tester, const MemoriesState(error: 'boom'));

      expect(find.byKey(const Key('memories_error')), findsOneWidget);
    });

    testWidgets('says what failed to load instead of "nothing yet"', (
      tester,
    ) async {
      await pump(tester, const MemoriesState(error: 'boom'));

      expect(find.byKey(const Key('memories_load_failed')), findsOneWidget);
      expect(find.text('Nothing remembered yet.'), findsNothing);
    });

    testWidgets('loads again from the retry button', (tester) async {
      await pump(tester, const MemoriesState(error: 'boom'));

      await tester.tap(find.byKey(const Key('memories_load_failed')));

      verify(() => bloc.add(const MemoriesRequested())).called(1);
    });

    testWidgets('names the limit a save broke and offers no retry', (
      tester,
    ) async {
      await pump(
        tester,
        const MemoriesState(
          error: MemoryValidationException('content is too long.'),
        ),
      );

      expect(find.textContaining('content is too long.'), findsOneWidget);
      expect(find.byKey(const Key('memories_load_failed')), findsNothing);
      expect(find.text('Nothing remembered yet.'), findsOneWidget);
    });

    testWidgets('says when a search finds nothing', (tester) async {
      await pump(tester, const MemoriesState());

      await tester.enterText(find.byType(TextField).last, 'tea');
      await tester.tap(find.byTooltip('Search'));
      await tester.pump();

      expect(find.byKey(const Key('memories_no_match')), findsOneWidget);
      expect(find.text('No memories match "tea".'), findsOneWidget);
    });

    testWidgets('shows progress while a search runs', (tester) async {
      await pump(tester, const MemoriesState(isRecalling: true));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('keeps the search text after searching', (tester) async {
      await pump(tester, const MemoriesState());

      await tester.enterText(find.byType(TextField).last, 'tea');
      await tester.tap(find.byTooltip('Search'));

      expect(find.text('tea'), findsOneWidget);
    });

    group('the text to remember', () {
      late StreamController<MemoriesState> states;

      setUp(() {
        states = StreamController<MemoriesState>();
        whenListen(bloc, states.stream, initialState: const MemoriesState());
      });

      tearDown(() => states.close());

      Future<void> pumpAndType(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<MemoriesBloc>.value(
              value: bloc,
              child: const MemoriesView(),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField).first, 'Likes tea');
      }

      testWidgets('stays when the save fails', (tester) async {
        await pumpAndType(tester);

        states.add(const MemoriesState(error: 'boom'));
        await tester.pump();

        expect(find.text('Likes tea'), findsOneWidget);
      });

      testWidgets('empties once the save worked', (tester) async {
        await pumpAndType(tester);

        states.add(
          const MemoriesState(lastOutcome: MemoryMutationOutcome(memory: _tea)),
        );
        await tester.pump();

        expect(find.text('Likes tea'), findsNothing);
      });
    });

    testWidgets('disables forget while a change is running', (tester) async {
      await pump(
        tester,
        MemoriesState(
          memories: [_memory('a', 'Likes tea')],
          inFlightMutationCount: 1,
        ),
      );

      final button = tester.widget<IconButton>(
        find.byKey(const Key('forget_a')),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('saves what is typed to remember', (tester) async {
      await pump(tester, const MemoriesState());

      await tester.enterText(find.byType(TextField).first, 'Likes tea');
      await tester.tap(find.byTooltip('Remember'));

      verify(
        () => bloc.add(
          const MemorySaved(
            NewMemory(content: 'Likes tea', kind: MemoryKind.topical),
          ),
        ),
      ).called(1);
    });

    testWidgets('recalls what is typed to search', (tester) async {
      await pump(tester, const MemoriesState());

      await tester.enterText(find.byType(TextField).last, 'tea');
      await tester.tap(find.byTooltip('Search'));

      verify(() => bloc.add(const MemoriesRecalled('tea'))).called(1);
    });

    testWidgets('forgets a memory', (tester) async {
      await pump(tester, MemoriesState(memories: [_memory('a', 'Likes tea')]));

      await tester.tap(find.byKey(const Key('forget_a')));

      verify(() => bloc.add(const MemoryRetired('a'))).called(1);
    });
  });
}
