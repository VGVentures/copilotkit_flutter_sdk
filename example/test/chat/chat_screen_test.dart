import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/chat_screen.dart';
import 'package:example/chat/composer.dart';
import 'package:example/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotChatBloc extends MockBloc<CopilotChatEvent, CopilotChatState>
    implements CopilotChatBloc;

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

class _MockCopilotAgent extends Mock implements CopilotAgent;

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(ChatPage, () {
    testWidgets('provides a chat bloc for the default agent', (tester) async {
      final client = _MockCopilotKitBloc();
      final agent = _MockCopilotAgent();
      when(() => client.state)
          .thenReturn(CopilotKitState(agents: {ChatPage.agentId: agent}));
      when(() => client.stream).thenAnswer((_) => const Stream.empty());
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
      verify(() => client.add(const AgentOpened(ChatPage.agentId))).called(1);
    });

    testWidgets('shows nothing until the agent is open', (tester) async {
      final client = _MockCopilotKitBloc();
      when(() => client.state).thenReturn(const CopilotKitState());
      when(() => client.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: const MaterialApp(home: ChatPage()),
        ),
      );

      expect(find.byType(ChatView), findsNothing);
    });
  });

  group(ChatView, () {
    late _MockCopilotChatBloc bloc;

    setUp(() => bloc = _MockCopilotChatBloc());

    Future<void> pump(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<CopilotChatBloc>.value(
            value: bloc,
            child: const ChatView(),
          ),
        ),
      );
    }

    testWidgets('shows the message list and the composer', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState());

      await pump(tester);

      expect(find.byType(MessageList), findsOneWidget);
      expect(find.byType(Composer), findsOneWidget);
      expect(find.byKey(const Key('chat_error')), findsNothing);
    });

    testWidgets('shows a notice when the last run failed', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState(error: 'boom'));

      await pump(tester);

      expect(find.byKey(const Key('chat_error')), findsOneWidget);
    });
  });
}
