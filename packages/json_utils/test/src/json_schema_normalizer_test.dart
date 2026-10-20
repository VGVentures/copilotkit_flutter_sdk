import 'package:json_utils/json_utils.dart';
import 'package:test/test.dart';

void main() {
  group(JsonSchemaNormalizer, () {
    const normalizer = JsonSchemaNormalizer();

    const empty = {
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{},
    };

    test('keeps a schema that already has properties', () {
      const schema = {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
        'additionalProperties': false,
      };

      expect(normalizer.normalize(schema), schema);
    });

    test('adds properties to an empty object', () {
      expect(
        normalizer.normalize(const {
          'type': 'object',
          'additionalProperties': false,
        }),
        empty,
      );
    });

    test('adds properties to nested empty objects', () {
      const object = {'type': 'object', 'additionalProperties': false};

      expect(
        normalizer.normalize(const {
          'type': 'object',
          'properties': {
            'plain': object,
            'nullable': {
              'anyOf': [
                object,
                {'type': 'null'},
              ],
            },
            'list': {'type': 'array', 'items': object},
            'deep': {
              'type': 'object',
              'properties': {'inner': object},
            },
            'map': {'type': 'object', 'additionalProperties': object},
            'negated': {'not': object},
          },
        }),
        {
          'type': 'object',
          'properties': {
            'plain': empty,
            'nullable': {
              'anyOf': [
                empty,
                {'type': 'null'},
              ],
            },
            'list': {'type': 'array', 'items': empty},
            'deep': {
              'type': 'object',
              'properties': {'inner': empty},
            },
            'map': {
              'type': 'object',
              'additionalProperties': empty,
              'properties': <String, Object?>{},
            },
            'negated': {'not': empty},
          },
        },
      );
    });

    test('keeps non-schema values under schema keys', () {
      const schema = {
        'type': 'array',
        'items': true,
        'oneOf': [false],
      };

      expect(normalizer.normalize(schema), schema);
    });

    test('never mutates the input schema', () {
      final schema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'inner': <String, Object?>{'type': 'object'},
        },
      };

      normalizer.normalize(schema);

      expect(schema, {
        'type': 'object',
        'properties': {
          'inner': {'type': 'object'},
        },
      });
    });
  });
}
