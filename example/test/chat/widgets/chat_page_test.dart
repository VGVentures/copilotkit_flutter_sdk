import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/chat_page.dart';
import 'package:example/chat/widgets/chat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

void main() {
  group(ChatPage, () {
    testWidgets('provides a chat bloc for the default agent', (tester) async {
      final client = _MockCopilotKitClient();
      final agent = _MockCopilotAgent();
      when(() => client.agent(ChatPage.agentId)).thenReturn(agent);
      when(() => agent.state).thenReturn(
        CopilotAgentState(
          agentId: ChatPage.agentId,
          threadId: 't',
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );
      when(() => agent.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: const MaterialApp(home: ChatPage()),
        ),
      );

      expect(find.byType(ChatView), findsOneWidget);
      expect(find.text('Hi'), findsOneWidget);
      verify(() => client.agent(ChatPage.agentId)).called(greaterThan(0));
    });
  });
}
