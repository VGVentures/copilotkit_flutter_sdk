import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotChatBloc extends MockBloc<CopilotChatEvent, CopilotChatState>
    implements CopilotChatBloc;

void main() {
  setUpAll(() => registerFallbackValue(const ChatStopRequested()));

  group(Composer, () {
    late _MockCopilotChatBloc bloc;

    setUp(() {
      bloc = _MockCopilotChatBloc();
      when(() => bloc.state).thenReturn(const CopilotChatState());
    });

    Future<void> pump(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<CopilotChatBloc>.value(
              value: bloc,
              child: const Composer(),
            ),
          ),
        ),
      );
    }

    IconButton button(WidgetTester tester) =>
        tester.widget<IconButton>(find.byType(IconButton));

    testWidgets('send is disabled while the input is blank', (tester) async {
      await pump(tester);
      expect(button(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(button(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.pump();
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('send adds the message and clears the input', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Weather in Lima?');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      verify(() => bloc.add(const ChatMessageSent('Weather in Lima?')))
          .called(1);
      expect(find.text('Weather in Lima?'), findsNothing);
    });

    testWidgets('the keyboard action sends too', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Hi');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      verify(() => bloc.add(const ChatMessageSent('Hi'))).called(1);
    });

    testWidgets('the keyboard action leaves blank input to the bloc', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '  ');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      // The bloc ignores blank messages.
      verify(() => bloc.add(const ChatMessageSent('  '))).called(1);
    });

    group('while running', () {
      setUp(() {
        when(() => bloc.state)
            .thenReturn(const CopilotChatState(isRunning: true));
      });

      testWidgets('shows stop, which stops the run', (tester) async {
        await pump(tester);
        expect(find.byIcon(Icons.send), findsNothing);

        await tester.tap(find.byIcon(Icons.stop));

        verify(() => bloc.add(const ChatStopRequested())).called(1);
      });

      testWidgets('keeps typed text but does not send it', (tester) async {
        await pump(tester);
        await tester.enterText(find.byType(TextField), 'Next question');

        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();

        verifyNever(() => bloc.add(any()));
        expect(find.text('Next question'), findsOneWidget);
      });
    });
  });
}
