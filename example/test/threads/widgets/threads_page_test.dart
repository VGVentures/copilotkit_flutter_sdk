import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/threads/widgets/threads_page.dart';
import 'package:example/threads/widgets/threads_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements CopilotKitClient;

class _MockThreadsClient extends Mock implements ThreadsClient;

void main() {
  group(ThreadsPage, () {
    testWidgets('loads the threads of the agent and shows them', (
      tester,
    ) async {
      final client = _MockClient();
      final threads = _MockThreadsClient();
      when(client.threadEndpoints).thenAnswer(
        (_) async => const ThreadEndpoints(list: true, mutations: true),
      );
      when(() => client.threads).thenReturn(threads);
      when(
        () => threads.list(
          agentId: any(named: 'agentId'),
          includeArchived: any(named: 'includeArchived'),
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => ThreadPage(
          threads: [
            ThreadRecord(
              id: 'a',
              agentId: 'default',
              archived: false,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              name: 'Trip',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ThreadsPage(
            client: client,
            agentId: 'default',
            currentThreadId: 'a',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ThreadsView), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      verify(() => threads.list(agentId: 'default')).called(1);
    });
  });
}
