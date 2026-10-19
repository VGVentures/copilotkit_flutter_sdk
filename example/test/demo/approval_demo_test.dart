import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/approval_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

ToolCallView _call({
  ToolCallStatus status = ToolCallStatus.executing,
  Map<String, Object?> args = const {'action': 'Delete 3 files'},
  String? result,
}) => ToolCallView(
  id: 'c1',
  name: 'confirmAction',
  status: status,
  args: args,
  result: result,
);

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(ApprovalDemo, () {
    testWidgets('registers the tool and renders its calls as a card', (
      tester,
    ) async {
      final client = _MockCopilotKitBloc();

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: ApprovalDemo(
              child: ToolCallWidget(
                call: const ToolCallView(
                  id: 'c1',
                  name: 'confirmAction',
                  status: ToolCallStatus.executing,
                  args: {'action': 'Delete 3 files'},
                  awaitingResponse: true,
                ),
              ),
            ),
          ),
        ),
      );

      final tool =
          verify(() => client.add(captureAny())).captured.single
              as ToolRegistered;
      expect(tool.tool, ApprovalDemo.tool);
      expect(tool.tool.parameters.toJsonSchema()['required'], ['action']);
      expect(find.text('Delete 3 files'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });
  });

  group(ApprovalCard, () {
    Future<void> pump(
      WidgetTester tester,
      ToolCallView call, {
      ToolCallResponder? respond,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalCard(call: call, respond: respond),
        ),
      ),
    );

    testWidgets('waits for the details while the arguments stream', (
      tester,
    ) async {
      await pump(
        tester,
        _call(status: ToolCallStatus.inProgress, args: const {}),
      );

      expect(find.text('Waiting for the details…'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('has no buttons until the call waits for the user', (
      tester,
    ) async {
      await pump(tester, _call());

      expect(find.text('Delete 3 files'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('approves with the decision', (tester) async {
      Object? answer;
      await pump(tester, _call(), respond: (result) => answer = result);

      await tester.tap(find.text('Approve'));

      expect(answer, {'decision': 'approve'});
    });

    testWidgets('rejects with the decision', (tester) async {
      Object? answer;
      await pump(tester, _call(), respond: (result) => answer = result);

      await tester.tap(find.text('Reject'));

      expect(answer, {'decision': 'reject'});
    });

    testWidgets('shows the answer once the call is complete', (tester) async {
      await pump(
        tester,
        _call(
          status: ToolCallStatus.complete,
          result: '{"decision":"approve"}',
        ),
      );

      expect(find.text('Answer: {"decision":"approve"}'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });
  });
}
