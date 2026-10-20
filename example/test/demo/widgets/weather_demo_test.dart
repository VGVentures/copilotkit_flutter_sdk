import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/demo_user.dart';
import 'package:example/demo/widgets/weather_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

void main() {
  setUpAll(() {
    registerFallbackValue(
      FrontendTool(
        name: 'fallback',
        description: '',
        parameters: Ack.object({}),
        decode: Map<String, Object?>.of,
        handler: (_, {required signal}) async => '',
      ),
    );
    registerFallbackValue(
      AgentContextEntry(description: '', value: DemoUser.ada.toJson()),
    );
  });

  group(WeatherDemo, () {
    testWidgets('registers the tool and the user context', (tester) async {
      final client = _MockCopilotKitClient();

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: const MaterialApp(
            home: WeatherDemo(child: ToolCallWidgetProbe()),
          ),
        ),
      );

      final tools = verify(() => client.registerTool(captureAny())).captured
          .cast<ClientTool<Object?>>();
      expect(tools.map((tool) => tool.name), ['confirmAction', 'showWeather']);
      final tool = tools.last;
      expect(tool.parameters.toJsonSchema()['required'], ['city']);
      final entry =
          verify(() => client.addContext(captureAny())).captured.single
              as AgentContextEntry;
      expect(entry.description, 'Current user');
      expect(entry.value, DemoUser.ada.toJson());
      expect(find.text('Checking Lima…'), findsOneWidget);
    });
  });
}

/// Renders a showWeather call inside the demo's tool scope.
class const ToolCallWidgetProbe({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ToolCallWidget(
      call: const ToolCallView(
        id: 'c1',
        name: 'showWeather',
        status: ToolCallStatus.executing,
        args: {'city': 'Lima'},
      ),
    );
  }
}
