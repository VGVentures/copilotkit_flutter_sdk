import 'dart:async';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/document/widgets/document_page.dart';
import 'package:example/document/widgets/document_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

class _MockUuid extends Mock implements Uuid;

CopilotAgentState _state({bool isRunning = false}) => CopilotAgentState(
  agentId: DocumentPage.agentId,
  threadId: 't',
  isRunning: isRunning,
);

void main() {
  setUpAll(() => registerFallbackValue(const UserMessage(id: '', content: '')));

  group(DocumentView, () {
    late _MockCopilotKitClient client;
    late _MockCopilotAgent agent;
    late StreamController<CopilotAgentState> states;

    setUp(() {
      client = _MockCopilotKitClient();
      agent = _MockCopilotAgent();
      states = StreamController<CopilotAgentState>.broadcast();
      addTearDown(states.close);
      when(() => client.agent(DocumentPage.agentId)).thenReturn(agent);
      when(() => agent.stream).thenAnswer((_) => states.stream);
      when(() => agent.state).thenReturn(_state());
      when(() => client.runAgent(any(), message: any(named: 'message')))
          .thenAnswer((_) async => true);
    });

    Future<void> pump(WidgetTester tester, {Widget? home}) {
      final uuid = _MockUuid();
      when(uuid.v4).thenReturn('m1');
      return tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home:
                home ??
                CopilotAgentScope(
                  agentId: DocumentPage.agentId,
                  child: DocumentView(uuid: uuid),
                ),
          ),
        ),
      );
    }

    testWidgets('asks the document agent with the trimmed prompt', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(
        find.byKey(const Key('document_prompt')),
        '  Write a haiku  ',
      );
      await tester.tap(find.byKey(const Key('document_send')));

      verify(
        () => client.runAgent(
          'document',
          message: const UserMessage(id: 'm1', content: 'Write a haiku'),
        ),
      ).called(1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('document_prompt')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('sends on the keyboard action and ignores blank text', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(find.byKey(const Key('document_prompt')), '  ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      verifyNever(() => client.runAgent(any(), message: any(named: 'message')));

      await tester.enterText(find.byKey(const Key('document_prompt')), 'Hi');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      verify(() => client.runAgent('document', message: any(named: 'message')))
          .called(1);
    });

    testWidgets('disables the prompt while the agent writes', (tester) async {
      await pump(tester);

      states.add(_state(isRunning: true));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const Key('document_prompt')),
      );
      final send = tester.widget<IconButton>(
        find.byKey(const Key('document_send')),
      );
      expect(field.enabled, isFalse);
      expect(send.onPressed, isNull);
    });

    testWidgets('DocumentPage opens the document agent', (tester) async {
      await pump(tester, home: DocumentPage(client: client));

      verify(() => client.agent('document')).called(greaterThanOrEqualTo(1));
      expect(find.text('Document'), findsOneWidget);
    });
  });
}
