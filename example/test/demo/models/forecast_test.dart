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

    group('tryParse', () {
      test('decodes a JSON forecast', () {
        final forecast = Forecast.tryParse(
          '{"city":"Lima","temperatureC":21,"condition":"Sunny"}',
        );

        expect(forecast?.city, 'Lima');
        expect(forecast?.temperatureC, 21);
        expect(forecast?.condition, 'Sunny');
      });

      for (final source in [
        null,
        '',
        'Tool call cancelled.',
        '[1, 2]',
        '{"city":"Lima"}',
        '{"city":"Lima","temperatureC":"warm","condition":"Sunny"}',
      ]) {
        test('returns null for $source', () {
          expect(Forecast.tryParse(source), isNull);
        });
      }
    });
  });
}
