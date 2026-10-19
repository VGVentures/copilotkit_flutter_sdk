import 'package:ack/ack.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:test/test.dart';

void main() {
  group(JsonSchemaEncoder, () {
    const encoder = JsonSchemaEncoder();

    test('keeps a schema that already has properties', () {
      expect(encoder.encode(Ack.object({'city': Ack.string()})), {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
        'additionalProperties': false,
      });
    });

    test('adds properties to an empty object', () {
      expect(encoder.encode(Ack.object({})), {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      });
    });

    test('adds properties to nested empty objects', () {
      final json = encoder.encode(
        Ack.object({
          'plain': Ack.object({}),
          'nullable': Ack.object({}).nullable(),
          'list': Ack.list(Ack.object({})),
          'deep': Ack.object({'inner': Ack.object({})}),
        }),
      );

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
