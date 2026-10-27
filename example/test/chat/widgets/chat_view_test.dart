import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/chat_view.dart';
import 'package:example/chat/widgets/composer.dart';
import 'package:example/chat/widgets/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotChatBloc extends MockBloc<CopilotChatEvent, CopilotChatState>
    implements CopilotChatBloc;

void main() {
  group(ChatView, () {
    late _MockCopilotChatBloc bloc;

    setUp(() => bloc = _MockCopilotChatBloc());

    Future<void> pump(WidgetTester tester, {Widget? header}) {
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<CopilotChatBloc>.value(
            value: bloc,
            child: ChatView(header: header),
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

    testWidgets('shows the header above the message list', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState());

      await pump(tester, header: const Text('Header'));

      expect(find.text('Header'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Header')).dy,
        lessThan(tester.getTopLeft(find.byType(MessageList)).dy),
      );
    });

    testWidgets('shows a notice when the last run failed', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState(error: 'boom'));

      await pump(tester);

      expect(find.byKey(const Key('chat_error')), findsOneWidget);
    });
  });
}
