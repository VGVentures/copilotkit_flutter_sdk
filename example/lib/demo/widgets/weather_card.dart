import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/forecast.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

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
    final forecast = _forecastFrom(result);
    if (forecast == null) return Text(result ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(forecast.city, style: textTheme.titleMedium),
        Text('${forecast.temperatureC}°C · ${forecast.condition}'),
      ],
    );
  }

  /// Decodes the JSON-encoded forecast in [result], or returns `null` when
  /// it isn't one, e.g. a cancellation or error message.
  Forecast? _forecastFrom(String? result) {
    if (result == null) return null;
    try {
      return switch (jsonDecode(result)) {
        final Map<String, Object?> json => Forecast.fromJson(json),
        _ => null,
      };
    } on FormatException {
      return null;
    } on CheckedFromJsonException {
      return null;
    }
  }
}
