import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/tool_schema.dart';
import 'package:test/test.dart';

void main() {
  group('ToolSchema toJson', () {
    test('keeps a schema that already has properties', () {
      expect(ToolSchema(Ack.object({'city': Ack.string()})).toJson(), {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
        'additionalProperties': false,
      });
    });

    test('adds properties to an empty object', () {
      expect(ToolSchema(Ack.object({})).toJson(), {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      });
    });

    test('adds properties to nested empty objects', () {
      final json = ToolSchema(
        Ack.object({
          'plain': Ack.object({}),
          'nullable': Ack.object({}).nullable(),
          'list': Ack.list(Ack.object({})),
          'deep': Ack.object({'inner': Ack.object({})}),
        }),
      ).toJson();

      const empty = {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      };
      final properties = json['properties']! as Map<String, Object?>;
      expect(properties['plain'], empty);
      expect(properties['nullable'], {
        'anyOf': [
          empty,
          {'type': 'null'},
        ],
      });
      expect(properties['list'], {'type': 'array', 'items': empty});
      expect((properties['deep']! as Map<String, Object?>)['properties'], {
        'inner': empty,
      });
    });
  });

  group('ToolSchema invalidArgumentsResult', () {
    final schema = Ack.object({
      'city': Ack.string(),
      'days': Ack.integer().optional(),
      'unit': Ack.object({'step': Ack.integer()}).optional(),
      'tags': Ack.list(Ack.string()).optional(),
    });

    String resultFor(Map<String, Object?> args) =>
        ToolSchema.invalidArgumentsResult(schema.safeParse(args).getError());

    test('lists each problem by argument path', () {
      expect(
        resultFor({'days': '3', 'extra': true}),
        "The tool didn't run: its arguments don't match its parameters. "
        'Fix them and call it again.\n'
        '- city: Required property "city" is missing.\n'
        '- days: Expected integer, got string.\n'
        '- extra: Property "extra" is not allowed.',
      );
    });

    test('joins nested paths with dots', () {
      expect(
        resultFor({
          'city': 'Lima',
          'unit': {'step': 'x'},
          'tags': ['a', 1],
        }),
        endsWith(
          '\n- unit.step: Expected integer, got string.'
          '\n- tags.1: Expected string, got integer.',
        ),
      );
    });

    test('describes a root error without a path', () {
      expect(
        ToolSchema.invalidArgumentsResult(schema.safeParse('Lima').getError()),
        endsWith('\n- Expected object, got string.'),
      );
    });
  });
}
