import 'dart:async';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/widgets/todo_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

CopilotAgentState _state(Map<String, Object?>? shared) => CopilotAgentState(
  agentId: 'default',
  threadId: 't',
  sharedState: shared == null ? null : SharedState(shared),
);

void main() {
  group(TodoPanel, () {
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
              body: CopilotAgentScope(agentId: 'default', child: TodoPanel()),
            ),
          ),
        ),
      );
    }

    SharedState captureEdit() {
      return verify(() => agent.setSharedState(captureAny())).captured.single
          as SharedState;
    }

    testWidgets('shows a hint while the state has no todos', (tester) async {
      await pump(tester, _state(null));

      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });

    testWidgets('ignores a state that is not a todo list', (tester) async {
      await pump(
        tester,
        _state(const {
          'todos': ['not a todo'],
        }),
      );

      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });

    testWidgets('shows the todos of the shared state', (tester) async {
      await pump(
        tester,
        _state(const {
          'todos': [
            {'title': 'Buy milk', 'done': false},
            {'title': 'Call Ada', 'done': true},
          ],
        }),
      );

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Call Ada'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byKey(const ValueKey('todo_1'))),
        isA<CheckboxListTile>().having((tile) => tile.value, 'value', isTrue),
      );
    });

    testWidgets('shows the todos the agent adds', (tester) async {
      await pump(tester, _state(null));

      states.add(
        _state(const {
          'todos': [
            {'title': 'Water the plants', 'done': false},
          ],
        }),
      );
      await tester.pump();

      expect(find.text('Water the plants'), findsOneWidget);
    });

    testWidgets('shares the todo the user adds', (tester) async {
      await pump(tester, _state(null));

      await tester.enterText(find.byType(TextField), '  Pay rent ');
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();

      expect(captureEdit().toJson(), {
        'todos': [
          {'title': 'Pay rent', 'done': false},
        ],
      });
      expect(find.widgetWithText(TextField, ''), findsOneWidget);
    });

    testWidgets('shares the todo the user submits from the keyboard', (
      tester,
    ) async {
      await pump(tester, _state(null));

      await tester.enterText(find.byType(TextField), 'Pay rent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(captureEdit().toJson(), {
        'todos': [
          {'title': 'Pay rent', 'done': false},
        ],
      });
    });

    testWidgets('does not add a blank todo', (tester) async {
      await pump(tester, _state(null));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Add'));

      verifyNever(() => agent.setSharedState(any()));
    });

    testWidgets('shares the todo the user ticks', (tester) async {
      await pump(
        tester,
        _state(const {
          'todos': [
            {'title': 'Buy milk', 'done': false},
          ],
        }),
      );

      await tester.tap(find.byType(Checkbox));

      expect(captureEdit().toJson(), {
        'todos': [
          {'title': 'Buy milk', 'done': true},
        ],
      });
    });

    testWidgets('shares the list without the todo the user removes', (
      tester,
    ) async {
      await pump(
        tester,
        _state(const {
          'todos': [
            {'title': 'Buy milk', 'done': false},
            {'title': 'Call Ada', 'done': false},
          ],
        }),
      );

      await tester.tap(find.byTooltip('Remove').first);

      expect(captureEdit().toJson(), {
        'todos': [
          {'title': 'Call Ada', 'done': false},
        ],
      });
    });
  });
}
