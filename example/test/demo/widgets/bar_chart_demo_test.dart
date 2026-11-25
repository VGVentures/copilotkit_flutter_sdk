import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/widgets/bar_chart_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

void main() {
  setUpAll(
    () => registerFallbackValue(
      FrontendTool(
        name: 'fallback',
        description: '',
        parameters: Ack.object({}),
        decode: Map<String, Object?>.of,
      ),
    ),
  );

  group(BarChartDemo, () {
    testWidgets('registers the component and renders its calls', (
      tester,
    ) async {
      final client = _MockCopilotKitClient();

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: Scaffold(
              body: BarChartDemo(
                child: ToolCallWidget(
                  call: const ToolCallView(
                    id: 'c1',
                    name: 'showBarChart',
                    status: ToolCallStatus.complete,
                    args: {
                      'title': 'Sales',
                      'bars': [
                        {'label': 'Q1', 'value': 3},
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final tool =
          verify(() => client.registerTool(captureAny())).captured.single
              as FrontendTool<Object?>;
      expect(tool.name, 'showBarChart');
      expect(tool.handler, isNull);
      expect(tool.parameters.toJsonSchema()['required'], ['title', 'bars']);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
    });
  });
}
