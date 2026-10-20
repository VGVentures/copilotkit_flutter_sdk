import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

/// Arguments of the weather tool in these tests.
class const _WeatherArgs(final String city) {
  factory fromJson(Map<String, Object?> json) =>
      _WeatherArgs(json['city']! as String);
}

void main() {
  group(ClientTool, () {
    test('is exhaustively matched over its kinds', () {
      String kind(ClientTool<Object?> tool) => switch (tool) {
        FrontendTool() => 'frontend',
        HumanInTheLoopTool() => 'human',
      };

      expect(
        kind(
          FrontendTool(
            name: 'a',
            description: 'A',
            parameters: Ack.object({}),
            decode: Map<String, Object?>.of,
            handler: (_, {required signal}) async => '',
          ),
        ),
        'frontend',
      );
      expect(
        kind(
          HumanInTheLoopTool(
            name: 'b',
            description: 'B',
            parameters: Ack.object({}),
            decode: Map<String, Object?>.of,
          ),
        ),
        'human',
      );
    });

    group('tryDecode', () {
      HumanInTheLoopTool<_WeatherArgs> tool() => HumanInTheLoopTool(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: Ack.object({'city': Ack.string()}),
        decode: _WeatherArgs.fromJson,
      );

      test('decodes the args', () {
        expect(tool().tryDecode(const {'city': 'Lima'})?.city, 'Lima');
      });

      test('returns null when decode throws', () {
        expect(tool().tryDecode(const {}), isNull);
        expect(tool().tryDecode(const {'city': 42}), isNull);
      });
    });
  });

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
      final result = await tool().run(const {
        'city': 'Lima',
      }, signal: CancellationSignal());

      expect(result, 'sunny in Lima');
    });

    test('run works through a tool of any argument type', () async {
      // The registry holds tools as ClientTool<Object?>.
      final ClientTool<Object?> anyTool = tool();

      final result = await (anyTool as FrontendTool<Object?>).run(const {
        'city': 'Lima',
      }, signal: CancellationSignal());

      expect(result, 'sunny in Lima');
    });

    test('run throws what the decoder throws', () {
      expect(
        () =>
            tool().run(const <String, Object?>{}, signal: CancellationSignal()),
        throwsA(isA<TypeError>()),
      );
    });

    test('supports value equality', () {
      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
    });
  });

  group(HumanInTheLoopTool, () {
    final parameters = Ack.object({'action': Ack.string()});

    HumanInTheLoopTool<Map<String, Object?>> tool({
      String name = 'confirmAction',
      bool followUp = true,
    }) => HumanInTheLoopTool(
      name: name,
      description: 'Ask the user to confirm an action',
      parameters: parameters,
      decode: Map<String, Object?>.of,
      followUp: followUp,
    );

    test('exposes its fields and follows up by default', () {
      final confirm = HumanInTheLoopTool(
        name: 'confirmAction',
        description: 'Ask the user to confirm an action',
        parameters: parameters,
        decode: Map<String, Object?>.of,
      );

      expect(confirm.name, 'confirmAction');
      expect(confirm.description, 'Ask the user to confirm an action');
      expect(confirm.parameters, same(parameters));
      expect(confirm.decode, Map<String, Object?>.of);
      expect(confirm.followUp, isTrue);
      expect(tool(followUp: false).followUp, isFalse);
    });

    test('supports value equality', () {
      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
      expect(tool(), isNot(tool(followUp: false)));
    });
  });
}
