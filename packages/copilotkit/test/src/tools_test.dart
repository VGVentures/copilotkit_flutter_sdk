import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(JsonSchema, () {
    test('raw returns the given map', () {
      const schema = JsonSchema.raw({'type': 'string', 'format': 'date'});

      expect(schema.toJson(), {'type': 'string', 'format': 'date'});
    });

    test('primitives encode their type and optional description', () {
      expect(JsonSchema.string().toJson(), {'type': 'string'});
      expect(JsonSchema.number(description: 'Temperature').toJson(), {
        'type': 'number',
        'description': 'Temperature',
      });
      expect(JsonSchema.integer().toJson(), {'type': 'integer'});
      expect(JsonSchema.boolean().toJson(), {'type': 'boolean'});
    });

    test('array encodes its items', () {
      expect(
        JsonSchema.array(JsonSchema.string(), description: 'Tags').toJson(),
        {
          'type': 'array',
          'description': 'Tags',
          'items': {'type': 'string'},
        },
      );
    });

    test('object encodes properties and required names', () {
      final schema = JsonSchema.object(
        {'city': JsonSchema.string(), 'days': JsonSchema.integer()},
        required: ['city'],
        description: 'Forecast request',
      );

      expect(schema.toJson(), {
        'type': 'object',
        'description': 'Forecast request',
        'properties': {
          'city': {'type': 'string'},
          'days': {'type': 'integer'},
        },
        'required': ['city'],
      });
    });

    test('object omits required when empty', () {
      expect(JsonSchema.object({}).toJson(), {
        'type': 'object',
        'properties': <String, Object?>{},
      });
    });
  });

  group(FrontendTool, () {
    test('exposes its fields and runs its handler', () async {
      final parameters = JsonSchema.object({'city': JsonSchema.string()});
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
        await tool.handler({'city': 'Lima'}, signal: CancellationSignal()),
        'sunny in Lima',
      );
    });
  });

  group(ToolCallView, () {
    test('defaults to empty args and no result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.inProgress,
      );

      expect(view.id, 'call-1');
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.inProgress);
      expect(view.args, isEmpty);
      expect(view.result, isNull);
    });

    test('holds args and result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: {'city': 'Lima'},
        result: 'sunny',
      );

      expect(view.args, {'city': 'Lima'});
      expect(view.result, 'sunny');
    });
  });

  group(CancellationSignal, () {
    test('starts not cancelled', () {
      expect(CancellationSignal().isCancelled, isFalse);
    });

    test('cancel marks it cancelled and completes whenCancelled', () async {
      final signal = CancellationSignal()..cancel();

      expect(signal.isCancelled, isTrue);
      await expectLater(signal.whenCancelled, completes);
    });

    test('cancel twice has no effect', () {
      final signal = CancellationSignal()
        ..cancel()
        ..cancel();

      expect(signal.isCancelled, isTrue);
    });
  });
}
