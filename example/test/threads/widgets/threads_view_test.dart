import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/threads/widgets/threads_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockThreadsBloc extends MockBloc<ThreadsEvent, ThreadsState>
    implements ThreadsBloc;

ThreadRecord _thread(String id, {String? name}) => ThreadRecord(
  id: id,
  agentId: 'default',
  archived: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026, 1, 2),
  name: name,
);

void main() {
  setUpAll(() => registerFallbackValue(const ThreadsRequested()));

  group(ThreadsView, () {
    late _MockThreadsBloc bloc;

    setUp(() => bloc = _MockThreadsBloc());

    /// Pushes the view from a home route, and returns what it pops with.
    Future<Future<String?> Function()> pump(
      WidgetTester tester,
      ThreadsState state, {
      String? current,
    }) async {
      when(() => bloc.state).thenReturn(state);
      String? popped;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider<ThreadsBloc>.value(
                      value: bloc,
                      child: ThreadsView(currentThreadId: current),
                    ),
                  ),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      return () async {
        await tester.pumpAndSettle();
        expect(done, isTrue);
        return popped;
      };
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a spinner while the first page loads', (tester) async {
      await pump(tester, const ThreadsState(isLoading: true));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('says when the runtime keeps no threads', (tester) async {
      await pump(tester, const ThreadsState(isAvailable: false));
      await open(tester);

      expect(find.byKey(const Key('threads_unavailable')), findsOneWidget);
    });

    testWidgets('offers a retry when loading failed', (tester) async {
      await pump(tester, const ThreadsState(error: 'boom'));
      await open(tester);

      await tester.tap(find.byKey(const Key('threads_error')));

      verify(() => bloc.add(const ThreadsRequested())).called(1);
    });

    testWidgets('says when there are no conversations', (tester) async {
      await pump(tester, const ThreadsState());
      await open(tester);

      expect(find.text('No conversations yet.'), findsOneWidget);
    });

    testWidgets('lists the threads and marks the current one', (tester) async {
      await pump(
        tester,
        ThreadsState(
          threads: [
            _thread('a', name: 'Trip'),
            _thread('b'),
          ],
        ),
        current: 'a',
      );
      await open(tester);

      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('New conversation'), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.byKey(const Key('thread_a'))).selected,
        isTrue,
      );
      expect(
        tester.widget<ListTile>(find.byKey(const Key('thread_b'))).selected,
        isFalse,
      );
    });

    testWidgets('returns the id of the thread that is tapped', (tester) async {
      final result = await pump(tester, ThreadsState(threads: [_thread('a')]));
      await open(tester);

      await tester.tap(find.byKey(const Key('thread_a')));

      expect(await result(), 'a');
    });

    testWidgets('returns a new id for a new conversation', (tester) async {
      final result = await pump(tester, const ThreadsState());
      await open(tester);

      await tester.tap(find.byKey(const Key('new_thread')));

      expect(await result(), isNotEmpty);
    });

    testWidgets('hides the thread actions when changes are not possible', (
      tester,
    ) async {
      await pump(tester, ThreadsState(threads: [_thread('a')]));
      await open(tester);

      expect(find.byKey(const Key('thread_menu_a')), findsNothing);
    });

    testWidgets('archives and deletes from the menu', (tester) async {
      await pump(
        tester,
        ThreadsState(threads: [_thread('a')], canMutate: true),
      );
      await open(tester);

      await tester.tap(find.byKey(const Key('thread_menu_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread_menu_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));

      verify(() => bloc.add(const ThreadArchived('a'))).called(1);
      verify(() => bloc.add(const ThreadDeleted('a'))).called(1);
    });
  });
}
