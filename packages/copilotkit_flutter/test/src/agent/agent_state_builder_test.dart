import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(AgentStateBuilder, () {
    late CopilotKitBloc client;
    late CopilotAgentBloc agent;
    late List<Object?> built;

    Future<void> pump(WidgetTester tester) async {
      // Created inside the test, so its events run in the fake async zone of
      // the widget tester, which `pump` advances.
      client = CopilotKitBloc(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
      );
      addTearDown(client.close);
      built = [];
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotAgentScope(
            agentId: 'ops',
            child: AgentStateBuilder<Object?>(
              selector: (state) => state.sharedState,
              builder: (context, shared) {
                built.add(shared);
                return Text('$shared', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      agent = client.state.agents['ops']!;
    }

    testWidgets('builds from the selected part of the state', (tester) async {
      await pump(tester);

      expect(find.text('null'), findsOneWidget);

      agent.add(const AgentStateSet({'count': 1}));
      await tester.pumpAndSettle();

      expect(find.text('{count: 1}'), findsOneWidget);
    });

    testWidgets('rebuilds only when the selected part changes', (tester) async {
      await pump(tester);
      agent.add(const AgentStateSet({'count': 1}));
      await tester.pumpAndSettle();
      built.clear();

      agent.add(AgentMessageAdded(UserMessage(id: 'u1', content: 'Hi')));
      await tester.pumpAndSettle();

      expect(built, isEmpty);
    });
  });
}
