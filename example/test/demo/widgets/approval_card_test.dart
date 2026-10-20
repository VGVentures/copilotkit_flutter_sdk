import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/approval_args.dart';
import 'package:example/demo/widgets/approval_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallView _call({
  ToolCallStatus status = ToolCallStatus.executing,
  String? result,
}) => ToolCallView(
  id: 'c1',
  name: 'confirmAction',
  status: status,
  result: result,
);

const _args = ApprovalArgs(action: 'Delete 3 files');

void main() {
  group(ApprovalCard, () {
    Future<void> pump(
      WidgetTester tester,
      ToolCallView call, {
      ApprovalArgs? args = _args,
      ToolCallResponder? respond,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalCard(call: call, args: args, respond: respond),
        ),
      ),
    );

    testWidgets('waits for the details while the arguments stream', (
      tester,
    ) async {
      await pump(tester, _call(status: ToolCallStatus.inProgress), args: null);

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
