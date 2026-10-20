import 'dart:convert';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/weather_args.dart';
import 'package:example/demo/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
