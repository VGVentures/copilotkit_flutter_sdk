import 'package:example/memories/widgets/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(TextEntry, () {
    late TextEditingController controller;

    setUp(() => controller = TextEditingController());
    tearDown(() => controller.dispose());

    Future<List<String>> pump(WidgetTester tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextEntry(
              controller: controller,
              hint: 'Hint',
              icon: Icons.add,
              tooltip: 'Go',
              onSubmit: submitted.add,
            ),
          ),
        ),
      );
      return submitted;
    }

    testWidgets('hands the trimmed text over and keeps it in the field', (
      tester,
    ) async {
      final submitted = await pump(tester);

      await tester.enterText(find.byType(TextField), '  likes tea ');
      await tester.tap(find.byTooltip('Go'));

      expect(submitted, ['likes tea']);
      expect(controller.text, '  likes tea ');
    });

    testWidgets('submits from the keyboard', (tester) async {
      final submitted = await pump(tester);

      await tester.enterText(find.byType(TextField), 'likes tea');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      expect(submitted, ['likes tea']);
    });

    testWidgets('ignores blank text', (tester) async {
      final submitted = await pump(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Go'));

      expect(submitted, isEmpty);
    });
  });
}
