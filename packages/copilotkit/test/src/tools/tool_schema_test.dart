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
}
