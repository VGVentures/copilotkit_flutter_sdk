import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolRegistry, () {
    FrontendTool tool(String name) => FrontendTool(
      name: name,
      description: 'A tool',
      parameters: Ack.object({}),
      handler: (_, {required signal}) async => 'ok',
    );

    test('starts empty', () {
      final registry = ToolRegistry();

      expect(registry.tools, isEmpty);
      expect(registry['showWeather'], isNull);
    });

    test('registers tools by name', () {
      final weather = tool('showWeather');
      final registry = ToolRegistry()..register(weather);

      expect(registry.tools, {'showWeather': weather});
      expect(registry['showWeather'], same(weather));
    });

    test('replaces a tool registered under the same name', () {
      final first = tool('showWeather');
      final second = tool('showWeather');
      final registry = ToolRegistry()
        ..register(first)
        ..register(second);

      expect(registry['showWeather'], same(second));
    });

    test('unregisters only the instance that is registered', () {
      final first = tool('showWeather');
      final second = tool('showWeather');
      final registry = ToolRegistry()
        ..register(first)
        ..register(second)
        ..unregister(first);

      expect(registry['showWeather'], same(second));

      registry.unregister(second);

      expect(registry.tools, isEmpty);
    });

    test('exposes a read-only view', () {
      final registry = ToolRegistry();

      expect(() => registry.tools['x'] = tool('x'), throwsUnsupportedError);
    });
  });
}
