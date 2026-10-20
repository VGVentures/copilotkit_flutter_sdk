import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/widgets/approval_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

void main() {
  setUpAll(() => registerFallbackValue(ApprovalDemo.tool));

  group(ApprovalDemo, () {
    testWidgets('registers the tool and renders its calls as a card', (
      tester,
    ) async {
      final client = _MockCopilotKitClient();

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
                  args: JsonObject({'action': 'Delete 3 files'}),
                  awaitingResponse: true,
                ),
              ),
            ),
          ),
        ),
      );

      final tool =
          verify(() => client.registerTool(captureAny())).captured.single
              as ClientTool<Object?>;
      expect(tool, ApprovalDemo.tool);
      expect(tool.parameters.toJsonSchema()['required'], ['action']);
      expect(find.text('Delete 3 files'), findsOneWidget);

      await tester.tap(find.text('Approve'));

      verify(() => client.respondToToolCall('c1', {'decision': 'approve'}))
          .called(1);
    });
  });
}
