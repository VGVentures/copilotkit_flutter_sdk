import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(AgentStateBuilder, () {
    late CopilotKitClient client;
    late List<Object?> built;

    setUp(() {
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
      );
      addTearDown(client.close);
      built = [];
    });

    Widget build({
      String agentId = 'ops',
      Object? Function(CopilotAgentState state)? selector,
    }) => CopilotKit.value(
      client: client,
      child: CopilotAgentScope(
        agentId: agentId,
        child: AgentStateBuilder<Object?>(
          selector: selector ?? (state) => state.sharedState?.toJson(),
          builder: (context, value) {
            built.add(value);
            return Text('$value', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );

    testWidgets('builds from the selected part of the state', (tester) async {
      await tester.pumpWidget(build());

      expect(find.text('null'), findsOneWidget);

      client.agent('ops').setSharedState(const SharedState({'count': 1}));
      await tester.pumpAndSettle();

      expect(find.text('{count: 1}'), findsOneWidget);
    });

    testWidgets('rebuilds only when the selected part changes', (tester) async {
      await tester.pumpWidget(build());
      built.clear();

      client
          .agent('ops')
          .addMessage(const UserMessage(id: 'u1', content: 'Hi'));
      await tester.pumpAndSettle();

      expect(built, isEmpty);
    });

    testWidgets('follows a new agent', (tester) async {
      client.agent('chat').setSharedState(const SharedState({'chat': true}));
      await tester.pumpWidget(build());
      await tester.pumpWidget(build(agentId: 'chat'));

      expect(find.text('{chat: true}'), findsOneWidget);

      client.agent('ops').setSharedState(const SharedState({'ops': true}));
      await tester.pumpAndSettle();

      expect(find.text('{chat: true}'), findsOneWidget);
    });

    testWidgets('selects again when the selector changes', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpWidget(build(selector: (state) => state.agentId));

      expect(find.text('ops'), findsOneWidget);
    });

    testWidgets('stops listening when removed', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpWidget(const SizedBox());
      built.clear();

      client.agent('ops').setSharedState(const SharedState({'count': 1}));
      await tester.pumpAndSettle();

      expect(built, isEmpty);
    });
  });
}
