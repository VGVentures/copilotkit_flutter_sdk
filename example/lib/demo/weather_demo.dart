// PLACEHOLDER DEMO CONTENT.
//
// A stand-in frontend tool and context so the full flow (generative UI and
// a context-based answer) can be checked on device before the demo scenario
// is chosen. Replace this file with the real scenario in task B10.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/demo_user.dart';
import 'package:example/demo/models/forecast.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/weather_service.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: registers the `showWeather` tool and the current user
/// context around [child].
class const WeatherDemo({
  required final Widget child,

  /// Looks up the weather when the agent calls the tool.
  final WeatherService _service = const WeatherService(),
  super.key,
}) extends StatelessWidget {
  // Keep in sync with WeatherArgs.
  static final ObjectSchema _parameters = Ack.object({
    'city': Ack.string().describe('City name, e.g. Lima'),
  });

  @override
  Widget build(BuildContext context) {
    return CopilotContext(
      description: 'Current user',
      value: DemoUser.ada,
      child: CopilotTool(
        tool: FrontendTool(
          name: 'showWeather',
          description:
              'Show the current weather for a city on the user '
              'screen.',
          parameters: _parameters,
          decode: WeatherArgs.fromJson,
          handler: _service.lookUp,
        ),
        builder: (context, call, args) => WeatherCard(call: call, args: args),
        child: child,
      ),
    );
  }
}

/// Placeholder generative UI for `showWeather` calls.
class const WeatherCard({
  /// The call to show.
  required final ToolCallView call,

  /// The arguments of [call], or `null` while they can't be decoded yet.
  final WeatherArgs? args,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final city = args?.city;
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
