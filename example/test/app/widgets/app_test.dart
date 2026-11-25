import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/app/app.dart';
import 'package:example/chat/widgets/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(App, () {
    testWidgets('opens the chat for a valid runtime URL', (tester) async {
      await tester.pumpWidget(
        const App(
          runtimeUrl: 'http://192.168.1.23:8200/api/copilotkit',
          threadId: 'thread-1',
        ),
      );

      expect(find.byType(ChatPage), findsOneWidget);
      final client = CopilotKit.of(tester.element(find.byType(ChatPage)));
      expect(client.agents.keys, [ChatPage.agentId]);
    });

    testWidgets('opens the chat on the saved thread', (tester) async {
      await tester.pumpWidget(
        const App(
          runtimeUrl: 'http://192.168.1.23:8200/api/copilotkit',
          threadId: 'thread-1',
        ),
      );

      final client = CopilotKit.of(tester.element(find.byType(ChatPage)));
      expect(client.agent(ChatPage.agentId).state.threadId, 'thread-1');
    });

    testWidgets('captures nothing unless learning is on', (tester) async {
      await tester.pumpWidget(
        const App(
          runtimeUrl: 'http://192.168.1.23:8200/api/copilotkit',
          threadId: 'thread-1',
        ),
      );
      expect(
        tester.widget<CopilotKit>(find.byType(CopilotKit)).learning,
        isNull,
      );

      await tester.pumpWidget(
        const App(
          runtimeUrl: 'http://192.168.1.23:8200/api/copilotkit',
          threadId: 'thread-1',
          learning: true,
        ),
      );
      await tester.pump();

      expect(
        tester.widget<CopilotKit>(find.byType(CopilotKit)).learning,
        const CopilotLearning(),
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.navigatorObservers!.single, isA<CopilotNavigatorObserver>());
    });

    testWidgets('explains how to set the runtime URL when missing', (
      tester,
    ) async {
      await tester.pumpWidget(const App(runtimeUrl: '', threadId: 'thread-1'));

      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('Runtime URL missing'), findsOneWidget);
      expect(find.textContaining('--dart-define=RUNTIME_URL='), findsOneWidget);
    });

    testWidgets('rejects a runtime URL without scheme and host', (
      tester,
    ) async {
      await tester.pumpWidget(
        const App(runtimeUrl: 'localhost:8200', threadId: 'thread-1'),
      );

      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('Runtime URL missing'), findsOneWidget);
    });
  });
}
