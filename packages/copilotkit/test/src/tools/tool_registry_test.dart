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

    test('counts an equal tool as another registration', () {
      Future<String> handler(
        Map<String, Object?> args, {
        required CancellationSignal signal,
      }) async => 'ok';
      FrontendTool<Map<String, Object?>> equalTool() => FrontendTool(
        name: 'showWeather',
        description: 'A tool',
        parameters: Ack.object({}),
        decode: Map<String, Object?>.of,
        handler: handler,
      );
      final first = equalTool();
      final second = equalTool();
      final registry = ToolRegistry()
        ..register(first)
        ..register(second);

      expect(registry.unregister(second), isFalse);
      expect(registry['showWeather'], same(first));

      expect(registry.unregister(first), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('keeps the count of a tool replaced by a different one', () {
      final first = tool('showWeather');
      final second = tool('showWeather');
      final registry = ToolRegistry()
        ..register(first)
        ..register(first)
        ..register(second);

      expect(registry.unregister(second), isFalse);
      expect(registry['showWeather'], same(first));

      expect(registry.unregister(first), isFalse);
      expect(registry['showWeather'], same(first));

      expect(registry.unregister(first), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('uses the tool registered last', () {
      final first = tool('showWeather');
      final second = tool('showWeather');
      final registry = ToolRegistry()
        ..register(first)
        ..register(second)
        ..register(first);

      expect(registry['showWeather'], same(first));

      expect(registry.unregister(first), isFalse);
      expect(registry['showWeather'], same(first));

      expect(registry.unregister(first), isFalse);
      expect(registry['showWeather'], same(second));
    });

    test('keeps a shared tool while one owner swaps away and back', () {
      final shared = tool('showWeather');
      final other = tool('showWeather');
      final registry = ToolRegistry()
        ..register(shared)
        ..register(shared)
        // One owner swaps to another tool: register the new one, then
        // unregister the old one.
        ..register(other);
      expect(registry.unregister(shared), isFalse);
      expect(registry['showWeather'], same(other));

      // It swaps back.
      registry.register(shared);
      expect(registry.unregister(other), isFalse);
      expect(registry['showWeather'], same(shared));

      // It is disposed; the other owner still holds the tool.
      expect(registry.unregister(shared), isFalse);
      expect(registry['showWeather'], same(shared));

      expect(registry.unregister(shared), isTrue);
      expect(registry.tools, isEmpty);
    });

    test('ignores a tool that is not registered', () {
      final registry = ToolRegistry()..register(tool('showWeather'));

      expect(registry.unregister(tool('showWeather')), isFalse);
      expect(registry.unregister(tool('showMap')), isFalse);
      expect(registry.tools, hasLength(1));
    });

    test('exposes a read-only view', () {
      final registry = ToolRegistry();

      expect(() => registry.tools['x'] = tool('x'), throwsUnsupportedError);
    });
  });
}
