import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/note_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(NoteDemo, () {
    testWidgets('registers the component and renders its calls as a card', (
      tester,
    ) async {
      final client = _MockCopilotKitBloc();

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: NoteDemo(
              child: ToolCallWidget(
                call: const ToolCallView(
                  id: 'c1',
                  name: 'showNote',
                  status: ToolCallStatus.complete,
                  args: {'title': 'Pack a coat', 'body': 'It is cold.'},
                ),
              ),
            ),
          ),
        ),
      );

      final registered =
          verify(() => client.add(captureAny())).captured.single
              as ToolRegistered;
      expect(registered.tool, isA<ComponentTool>());
      expect(registered.tool.name, 'showNote');
      expect(registered.tool.parameters.toJsonSchema()['required'], [
        'title',
        'body',
      ]);
      expect(find.text('Pack a coat'), findsOneWidget);
      expect(find.text('It is cold.'), findsOneWidget);
    });
  });

  group(NoteCard, () {
    Future<void> pump(
      WidgetTester tester,
      Map<String, Object?> args,
      ToolCallStatus status,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCard(args: args, status: status),
        ),
      ),
    );

    testWidgets('fills in as the arguments stream', (tester) async {
      await pump(tester, const {}, ToolCallStatus.inProgress);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await pump(tester, const {
        'title': 'Pack a coat',
      }, ToolCallStatus.inProgress);
      expect(find.text('Pack a coat'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the title and the body when complete', (tester) async {
      await pump(tester, const {
        'title': 'Pack a coat',
        'body': 'It is cold.',
      }, ToolCallStatus.complete);

      expect(find.text('Pack a coat'), findsOneWidget);
      expect(find.text('It is cold.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('ignores arguments that are not text', (tester) async {
      await pump(tester, const {
        'title': 1,
        'body': true,
      }, ToolCallStatus.complete);

      expect(find.byType(Text), findsNothing);
    });
  });
}
