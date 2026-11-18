import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/memories_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMemoriesBloc extends MockBloc<MemoriesEvent, MemoriesState>
    implements MemoriesBloc;

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
