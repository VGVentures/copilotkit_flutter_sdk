import 'package:ack/ack.dart';
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
    Future<void> pump(
      WidgetTester tester,
      CopilotKitClient client, {
      ToolCallView call = const ToolCallView(
        id: 'c1',
        name: 'showWeather',
        status: ToolCallStatus.executing,
        args: {'city': 'Lima'},
      ),
    }) {
      return tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: WeatherDemo(child: ToolCallWidgetProbe(call: call)),
          ),
        ),
      );
    }

    testWidgets('registers the tool and the user context', (tester) async {
      final client = _MockCopilotKitClient();

      await pump(tester, client);

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

    testWidgets('renders a completed call as its forecast', (tester) async {
      await pump(
        tester,
        _MockCopilotKitClient(),
        call: const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
          args: {'city': 'Lima'},
          result: '{"city":"Lima","temperatureC":21,"condition":"Sunny"}',
        ),
      );

      expect(find.text('Lima'), findsOneWidget);
      expect(find.text('21°C · Sunny'), findsOneWidget);
    });
  });
}

/// Renders a showWeather [call] inside the demo's tool scope.
class const ToolCallWidgetProbe({required final ToolCallView call, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ToolCallWidget(call: call);
}
