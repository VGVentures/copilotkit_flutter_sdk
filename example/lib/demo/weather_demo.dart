// PLACEHOLDER DEMO CONTENT.
//
// A stand-in frontend tool and context so the full flow (generative UI and
// a context-based answer) can be checked on device before the demo scenario
// is chosen. Replace this file with the real scenario in task B10.
import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/approval_demo.dart';
import 'package:example/demo/models/forecast.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/note_demo.dart';
import 'package:flutter/material.dart';

/// Placeholder user shared with the agent as context.
const demoUser = {'name': 'Ada', 'homeCity': 'Lima'};

const _conditions = ['Sunny', 'Cloudy', 'Rainy', 'Windy', 'Foggy'];

/// Placeholder tool handler: a fake, offline forecast for `args['city']`.
///
/// Deterministic per city so demos are repeatable. Waits [delay] so the
/// executing state is visible. Throws when [args] don't match [WeatherArgs].
Future<String> lookUpWeather(
  Map<String, Object?> args, {
  required CancellationSignal signal,
  Duration delay = const Duration(seconds: 1),
}) async {
  await Future<void>.delayed(delay);
  if (signal.isCancelled) return 'Cancelled';
  final city = WeatherArgs.fromJson(args).city ?? 'Unknown';
  final seed = city.codeUnits.fold(0, (sum, unit) => sum + unit);
  final forecast = Forecast(
    city: city,
    temperatureC: 12 + seed % 18,
    condition: _conditions[seed % _conditions.length],
  );
  return jsonEncode(forecast);
}

/// Placeholder demo: registers the `showWeather` tool, the `confirmAction`
/// approval tool (see [ApprovalDemo]), the `showNote` component (see
/// [NoteDemo]) and the current user context around [child].
class const WeatherDemo({required final Widget child, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CopilotContext(
      description: 'Current user',
      value: demoUser,
      child: ApprovalDemo(
        child: NoteDemo(
          child: CopilotTool(
            tool: _showWeather,
            builder: (context, call) => WeatherCard(call: call),
            child: child,
          ),
        ),
      ),
    );
  }
}

final _showWeather = FrontendTool(
  name: 'showWeather',
  description: 'Show the current weather for a city on the user screen.',
  // Keep in sync with WeatherArgs.
  parameters: Ack.object({
    'city': Ack.string().describe('City name, e.g. Lima'),
  }),
  handler: lookUpWeather,
);

/// Placeholder generative UI for `showWeather` calls.
class const WeatherCard({required final ToolCallView call, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final city = WeatherArgs.tryParse(call.args)?.city;
    final content = switch (call.status) {
      ToolCallStatus.inProgress => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Looking up the weather…'),
          SizedBox(height: 8),
          LinearProgressIndicator(),
        ],
      ),
      ToolCallStatus.executing => Text('Checking ${city ?? 'the city'}…'),
      ToolCallStatus.complete => _forecast(call.result, textTheme),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_outlined, size: 32),
            const SizedBox(width: 16),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _forecast(String? result, TextTheme textTheme) {
    final forecast = Forecast.tryParse(result);
    if (forecast == null) return Text(result ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(forecast.city, style: textTheme.titleMedium),
        Text('${forecast.temperatureC}°C · ${forecast.condition}'),
      ],
    );
  }
}
