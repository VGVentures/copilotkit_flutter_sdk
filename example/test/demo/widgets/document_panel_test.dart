import 'dart:async';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/widgets/document_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

CopilotAgentState _state(
  Map<String, Object?>? shared, {
  bool isRunning = false,
}) => CopilotAgentState(
  agentId: 'default',
  threadId: 't',
  sharedState: shared == null ? null : SharedState(shared),
  isRunning: isRunning,
);

void main() {
  setUpAll(() => registerFallbackValue(const SharedState({})));

  group(DocumentPanel, () {
    late _MockCopilotAgent agent;
    late StreamController<CopilotAgentState> states;

    setUp(() {
      agent = _MockCopilotAgent();
      states = StreamController<CopilotAgentState>.broadcast();
      addTearDown(states.close);
      when(() => agent.stream).thenAnswer((_) => states.stream);
    });

    Future<void> pump(WidgetTester tester, CopilotAgentState state) {
      final client = _MockCopilotKitClient();
      when(() => client.agent('default')).thenReturn(agent);
      when(() => agent.state).thenReturn(state);
      return tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: const MaterialApp(
            home: Scaffold(
              body: CopilotAgentScope(
                agentId: 'default',
                child: DocumentPanel(),
              ),
            ),
          ),
        ),
      );
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('shows a hint while the state has no document', (tester) async {
      await pump(tester, _state(const {'todos': <Object?>[]}));

      expect(find.textContaining('No document yet'), findsOneWidget);
      expect(fieldText(tester), isEmpty);
    });

    testWidgets('shows a hint without a shared state', (tester) async {
      await pump(tester, _state(null));

      expect(find.textContaining('No document yet'), findsOneWidget);
    });

    testWidgets('shows a hint when the document is not a string', (
      tester,
    ) async {
      await pump(tester, _state(const {'document': 42}));

      expect(find.textContaining('No document yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the document of the shared state', (tester) async {
      await pump(tester, _state(const {'document': 'Dear Ada,'}));

      expect(fieldText(tester), 'Dear Ada,');
    });

    testWidgets('renders the document as the agent streams it', (tester) async {
      await pump(tester, _state(null, isRunning: true));

      for (final partial in ['Dear', 'Dear Ada,', 'Dear Ada,\nHello']) {
        states.add(_state({'document': partial}, isRunning: true));
        await tester.pump();

        expect(fieldText(tester), partial);
      }
    });

    testWidgets('shows the LIVE badge while the agent runs', (tester) async {
      await pump(tester, _state(const {'document': 'Hi'}, isRunning: true));

      expect(find.text('LIVE'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    });

    testWidgets('shows and hides the LIVE badge as the run starts and ends', (
      tester,
    ) async {
      await pump(tester, _state(const {'document': 'Hi'}));
      expect(find.text('LIVE'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );

      states.add(_state(const {'document': 'Hi'}, isRunning: true));
      await tester.pump();
      expect(find.text('LIVE'), findsOneWidget);

      states.add(_state(const {'document': 'Hi there'}));
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsNothing);
      expect(fieldText(tester), 'Hi there');
    });

    testWidgets('shares the edit of the user and keeps the rest of the state', (
      tester,
    ) async {
      await pump(
        tester,
        _state(const {
          'document': 'Dear Ada,',
          'todos': [
            {'title': 'Buy milk', 'done': false},
          ],
        }),
      );

      await tester.enterText(find.byType(TextField), 'Dear Grace,');

      final shared =
          verify(() => agent.setSharedState(captureAny())).captured.single
              as SharedState;
      expect(shared.toJson(), {
        'document': 'Dear Grace,',
        'todos': [
          {'title': 'Buy milk', 'done': false},
        ],
      });
    });

    testWidgets('keeps the text the user typed when the state echoes it', (
      tester,
    ) async {
      await pump(tester, _state(const {'document': 'Hi'}));

      await tester.enterText(find.byType(TextField), 'Hi!');
      states.add(_state(const {'document': 'Hi!'}));
      await tester.pump();

      expect(fieldText(tester), 'Hi!');
    });
  });
}
