import 'package:example/demo/models/weather_args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

void main() {
  group(WeatherArgs, () {
    test('decodes the city', () {
      expect(WeatherArgs.fromJson({'city': 'Lima'}).city, 'Lima');
    });

    test('allows a missing city', () {
      expect(WeatherArgs.fromJson({}).city, isNull);
    });

    test('rejects a city that is not a string', () {
      expect(
        () => WeatherArgs.fromJson({'city': 42}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('encodes to JSON', () {
      expect(const WeatherArgs(city: 'Lima').toJson(), {'city': 'Lima'});
      expect(const WeatherArgs().toJson(), isEmpty);
    });
  });
}
