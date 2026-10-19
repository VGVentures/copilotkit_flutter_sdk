import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/forecast.dart';
import 'package:example/demo/models/weather_args.dart';

/// Placeholder weather lookups: a fake, offline forecast per city.
class const WeatherService({
  /// How long a lookup takes, so the executing state is visible.
  final Duration _delay = const Duration(seconds: 1),
}) {
  /// Creates a service whose lookups take `delay`.
  this;

  static const _conditions = ['Sunny', 'Cloudy', 'Rainy', 'Windy', 'Foggy'];

  /// Returns a JSON-encoded [Forecast] for the city in [args], or
  /// `Cancelled` when [signal] is cancelled during the lookup.
  ///
  /// Deterministic per city so demos are repeatable.
  Future<String> lookUp(
    WeatherArgs args, {
    required CancellationSignal signal,
  }) async {
    await Future<void>.delayed(_delay);
    if (signal.isCancelled) return 'Cancelled';
    final city = args.city ?? 'Unknown';
    final seed = city.codeUnits.fold(0, (sum, unit) => sum + unit);
    final forecast = Forecast(
      city: city,
      temperatureC: 12 + seed % 18,
      condition: _conditions[seed % _conditions.length],
    );
    return jsonEncode(forecast);
  }
}
