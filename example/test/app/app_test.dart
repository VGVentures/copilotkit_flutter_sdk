import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/app/app.dart';
import 'package:example/chat/chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(App, () {
    testWidgets('opens the chat for a valid runtime URL', (tester) async {
      await tester.pumpWidget(
        const App(runtimeUrl: 'http://192.168.1.23:8200/api/copilotkit'),
      );

      expect(find.byType(ChatPage), findsOneWidget);
      final client = CopilotKit.of(tester.element(find.byType(ChatPage)));
      expect(
        client.runtimeUrl,
        Uri.parse('http://192.168.1.23:8200/api/copilotkit'),
      );
      expect(client.onError, isNotNull);
      client.onError!(Exception('logged, not thrown'), StackTrace.current);
    });

    testWidgets('explains how to set the runtime URL when missing', (
      tester,
    ) async {
      await tester.pumpWidget(const App(runtimeUrl: ''));

      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('Runtime URL missing'), findsOneWidget);
      expect(find.textContaining('--dart-define=RUNTIME_URL='), findsOneWidget);
    });

    testWidgets('rejects a runtime URL without scheme and host', (
      tester,
    ) async {
      await tester.pumpWidget(const App(runtimeUrl: 'localhost:8200'));

      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('Runtime URL missing'), findsOneWidget);
    });
  });
}
