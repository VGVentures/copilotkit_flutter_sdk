import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(FrontendTool, () {
    test('exposes its fields and runs its handler', () async {
      final parameters = Ack.object({'city': Ack.string()});
      final tool = FrontendTool(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: parameters,
        handler: (args, {required signal}) async => 'sunny in ${args['city']}',
      );

      expect(tool.name, 'showWeather');
      expect(tool.description, 'Show the weather for a city');
      expect(tool.parameters, same(parameters));
      expect(
        await tool.handler({
          'city': 'Lima',
        }, signal: const CancellationSignal.none()),
        'sunny in Lima',
      );
    });

    test('supports value equality', () {
      final parameters = Ack.object({'city': Ack.string()});
      Future<String> handler(
        Map<String, Object?> args, {
        required CancellationSignal signal,
      }) async => 'sunny';
      FrontendTool tool({String name = 'showWeather'}) => FrontendTool(
        name: name,
        description: 'Show the weather',
        parameters: parameters,
        handler: handler,
      );

      expect(tool(), tool());
      expect(tool(), isNot(tool(name: 'other')));
    });
  });
}
