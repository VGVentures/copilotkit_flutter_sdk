import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolRegistry, () {
    FrontendTool<Map<String, Object?>> tool(String name) => FrontendTool(
      name: name,
      description: 'A tool',
      parameters: Ack.object({}),
      decode: Map<String, Object?>.of,
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

    test('unregisters only the tool that is registered', () {
      final first = tool('showWeather');
      final second = FrontendTool<Map<String, Object?>>(
        name: 'showWeather',
        description: 'Another tool',
        parameters: Ack.object({}),
        decode: Map<String, Object?>.of,
        handler: (_, {required signal}) async => 'ok',
      );
      final registry = ToolRegistry()
        ..register(first)
        ..register(second);

      expect(registry.unregister(first), isFalse);
      expect(registry['showWeather'], same(second));

      expect(registry.unregister(second), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('keeps a tool registered twice until both unregister it', () {
      final weather = tool('showWeather');
      final registry = ToolRegistry()
        ..register(weather)
        ..register(weather);

      expect(registry.unregister(weather), isFalse);
      expect(registry['showWeather'], same(weather));

      expect(registry.unregister(weather), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('counts a replacing tool from one registration', () {
      final first = FrontendTool<Map<String, Object?>>(
        name: 'showWeather',
        description: 'Another tool',
        parameters: Ack.object({}),
        decode: Map<String, Object?>.of,
        handler: (_, {required signal}) async => 'ok',
      );
      final second = tool('showWeather');
      final registry = ToolRegistry()
        ..register(first)
        ..register(first)
        ..register(second);

      expect(registry.unregister(second), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('exposes a read-only view', () {
      final registry = ToolRegistry();

      expect(() => registry.tools['x'] = tool('x'), throwsUnsupportedError);
    });
  });
}
