import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/demo_user.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/weather_demo.dart';
import 'package:example/demo/weather_service.dart';
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
        decode: JsonObject.new,
        handler: (_, {required signal}) async => '',
      ),
    );
    registerFallbackValue(
      AgentContextEntry(description: '', value: DemoUser.ada),
    );
  });

  group(WeatherService, () {
    const service = WeatherService(delay: Duration.zero);

    test('returns a deterministic forecast for the city', () async {
      Future<String> lookUp() => service.lookUp(
        const WeatherArgs(city: 'Lima'),
        signal: CancellationSignal(),
      );

      final first = await lookUp();
      final second = await lookUp();

      final forecast = jsonDecode(first) as Map<String, Object?>;
      expect(forecast['city'], 'Lima');
      expect(forecast['temperatureC'], isA<int>());
      expect(forecast['condition'], isA<String>());
      expect(second, first);
    });

    test('falls back to an unknown city', () async {
      final result = await service.lookUp(
        const WeatherArgs(),
        signal: CancellationSignal(),
      );

      final forecast = jsonDecode(result) as Map<String, Object?>;
      expect(forecast['city'], 'Unknown');
    });

    test('reports a cancelled lookup', () async {
      final result = await service.lookUp(
        const WeatherArgs(city: 'Lima'),
        signal: CancellationSignal()..cancel(),
      );

      expect(result, 'Cancelled');
    });
  });

  group(WeatherCard, () {
    Future<void> pump(WidgetTester tester, ToolCallView call) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeatherCard(
              call: call,
              args: call.args.tryDecode(WeatherArgs.fromJson),
            ),
          ),
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
          args: JsonObject({'city': 'Lima'}),
        ),
      );

      expect(find.text('Checking Lima…'), findsOneWidget);
    });

    testWidgets('names no city while the lookup runs without one', (
      tester,
    ) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.executing,
        ),
      );

      expect(find.text('Checking the city…'), findsOneWidget);
    });

    testWidgets('names no city when the city is not a string', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.executing,
          args: JsonObject({'city': 42}),
        ),
      );

      expect(find.text('Checking the city…'), findsOneWidget);
    });

    testWidgets('shows the forecast when complete', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
          args: JsonObject({'city': 'Lima'}),
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

    for (final result in [
      '[1, 2]',
      '{"city":"Lima"}',
      '{"city":"Lima","temperatureC":"warm","condition":"Sunny"}',
    ]) {
      testWidgets('shows a malformed forecast as text: $result', (
        tester,
      ) async {
        await pump(
          tester,
          ToolCallView(
            id: 'c1',
            name: 'showWeather',
            status: ToolCallStatus.complete,
            result: result,
          ),
        );

        expect(find.text(result), findsOneWidget);
      });
    }

    testWidgets('shows an empty text without a result', (tester) async {
      await pump(
        tester,
        const ToolCallView(
          id: 'c1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
        ),
      );

      expect(find.text(''), findsOneWidget);
    });
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

      final tool =
          verify(() => client.registerTool(captureAny())).captured.single
              as FrontendTool<Object?>;
      expect(tool.name, 'showWeather');
      expect(tool.parameters.toJsonSchema()['required'], ['city']);
      final entry =
          verify(() => client.addContext(captureAny())).captured.single
              as AgentContextEntry;
      expect(entry.description, 'Current user');
      expect(entry.value, DemoUser.ada);
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
        args: JsonObject({'city': 'Lima'}),
      ),
    );
  }
}
