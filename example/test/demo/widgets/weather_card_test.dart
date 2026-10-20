import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/widgets/weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
