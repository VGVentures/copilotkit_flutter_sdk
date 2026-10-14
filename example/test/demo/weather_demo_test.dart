import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/weather_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockAgentContextEntry extends Mock implements AgentContextEntry;

FrontendTool _fallbackTool() => FrontendTool(
  name: 'x',
  description: 'x',
  parameters: JsonSchema.object({}),
  handler: (args, {required signal}) async => '',
);

void main() {
  setUpAll(() => registerFallbackValue(_fallbackTool()));

  group('lookUpWeather', () {
    test('returns a deterministic forecast for the city', () async {
      final first = await lookUpWeather(
        {'city': 'Lima'},
        signal: CancellationSignal(),
        delay: Duration.zero,
      );
      final second = await lookUpWeather(
        {'city': 'Lima'},
        signal: CancellationSignal(),
        delay: Duration.zero,
      );

      final forecast = jsonDecode(first) as Map<String, Object?>;
      expect(forecast['city'], 'Lima');
      expect(forecast['temperatureC'], isA<int>());
      expect(forecast['condition'], isA<String>());
      expect(second, first);
    });

    test('falls back to an unknown city', () async {
      final forecast = jsonDecode(
        await lookUpWeather(
          {},
          signal: CancellationSignal(),
          delay: Duration.zero,
        ),
      ) as Map<String, Object?>;

      expect(forecast['city'], 'Unknown');
    });

    test('reports a cancelled lookup', () async {
      final result = await lookUpWeather(
        {'city': 'Lima'},
        signal: CancellationSignal()..cancel(),
        delay: Duration.zero,
      );

      expect(result, 'Cancelled');
    });
  });

  group(WeatherCard, () {
    Future<void> pump(WidgetTester tester, ToolCallView call) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeatherCard(call: call)),
        ),
      );
    }

    testWidgets('shows a loading state while args stream', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.inProgress,
        ),
      );

      expect(find.text('Looking up the weather…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the city while the lookup runs', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.executing,
          args: {'city': 'Lima'},
        ),
      );

      expect(find.text('Checking Lima…'), findsOneWidget);
    });

    testWidgets('shows the forecast when complete', (tester) async {
      await pump(
        tester,
        const ToolCallView(
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

    testWidgets('shows a non-forecast result as text', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
          result: 'Tool call cancelled.',
        ),
      );

      expect(find.text('Tool call cancelled.'), findsOneWidget);
    });
  });

  group(WeatherDemo, () {
    testWidgets('registers the tool and the user context', (tester) async {
      final client = _MockCopilotKitClient();
      when(() => client.registerTool(any())).thenReturn(() {});
      when(() => client.addContext(any(), any()))
          .thenReturn(_MockAgentContextEntry());

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: const MaterialApp(
            home: WeatherDemo(child: ToolCallWidgetProbe()),
          ),
        ),
      );

      final tool =
          verify(() => client.registerTool(captureAny())).captured.single
              as FrontendTool;
      expect(tool.name, 'showWeather');
      expect(tool.parameters.toJson()['required'], ['city']);
      verify(() => client.addContext('Current user', demoUser)).called(1);
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
