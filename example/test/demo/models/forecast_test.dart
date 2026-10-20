import 'package:example/demo/models/forecast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

void main() {
  group(Forecast, () {
    test('round-trips through JSON', () {
      const forecast = Forecast(
        city: 'Lima',
        temperatureC: 21,
        condition: 'Sunny',
      );

      final decoded = Forecast.fromJson(forecast.toJson());

      expect(forecast.toJson(), {
        'city': 'Lima',
        'temperatureC': 21,
        'condition': 'Sunny',
      });
      expect(decoded.city, forecast.city);
      expect(decoded.temperatureC, forecast.temperatureC);
      expect(decoded.condition, forecast.condition);
    });

    test('rejects a missing field', () {
      expect(
        () => Forecast.fromJson({'city': 'Lima', 'condition': 'Sunny'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });
}
