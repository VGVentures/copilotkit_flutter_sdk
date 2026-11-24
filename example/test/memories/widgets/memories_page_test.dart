import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/memories/widgets/memories_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMemoriesClient extends Mock implements MemoriesClient;

void main() {
  group(MemoriesPage, () {
    testWidgets('loads the memories and shows them', (tester) async {
      final client = _MockMemoriesClient();
      when(
        () => client.list(includeInvalidated: any(named: 'includeInvalidated')),
      ).thenAnswer(
        (_) async => const [
          Memory(
            id: 'a',
            kind: MemoryKind.topical,
            scope: MemoryScope.user,
            content: 'Likes tea',
            sourceThreadIds: [],
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(home: MemoriesPage(client: client)));
      await tester.pumpAndSettle();

      expect(find.text('Likes tea'), findsOneWidget);
    });
  });
}
