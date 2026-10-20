import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

/// Arguments of the weather tool in these tests.
class const _WeatherArgs(final String city) {
  factory fromJson(Map<String, Object?> json) =>
      _WeatherArgs(json['city']! as String);
}

void main() {
  group(FrontendTool, () {
    final parameters = Ack.object({'city': Ack.string()});

    Future<String> handler(
      _WeatherArgs args, {
      required CancellationSignal signal,
    }) async => 'sunny in ${args.city}';

    FrontendTool<_WeatherArgs> tool({String name = 'showWeather'}) =>
        FrontendTool(
          name: name,
          description: 'Show the weather for a city',
          parameters: parameters,
          decode: _WeatherArgs.fromJson,
          handler: handler,
        );

    test('exposes its fields', () {
      final weather = tool();

      expect(weather.name, 'showWeather');
      expect(weather.description, 'Show the weather for a city');
      expect(weather.parameters, same(parameters));
      expect(weather.decode, _WeatherArgs.fromJson);
      expect(weather.handler, handler);
    });

    test('run decodes the args and runs the handler', () async {
      final result = await tool().run(
        const JsonObject({'city': 'Lima'}),
        signal: CancellationSignal(),
      );

      expect(result, 'sunny in Lima');
    });

    test('run works through a tool of any argument type', () async {
      // The registry holds tools as FrontendTool<Object?>.
      final FrontendTool<Object?> anyTool = tool();

      final result = await anyTool.run(
        const JsonObject({'city': 'Lima'}),
        signal: CancellationSignal(),
      );

      expect(result, 'sunny in Lima');
    });

    test('run throws what the decoder throws', () {
      expect(
        () => tool().run(const JsonObject(), signal: CancellationSignal()),
        throwsA(isA<TypeError>()),
      );
    });

    test('supports value equality', () {
      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
    });
  });
}
