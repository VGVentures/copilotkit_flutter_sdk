import 'package:ack/ack.dart';

/// Encodes [schema] as the JSON Schema sent in `RunAgentInput.tools`.
///
/// Ack omits `properties` on empty objects, at any depth, and some providers
/// reject object schemas without it, so every object schema gets an empty
/// `properties` map when it has none.
Map<String, Object?> toolParametersJson(ObjectSchema schema) =>
    _withProperties(schema.toJsonSchema());

/// Keys whose value is a subschema.
const _schemaKeys = {'items', 'additionalProperties', 'not'};

/// Keys whose value is a list of subschemas.
const _schemaListKeys = {'anyOf', 'oneOf', 'allOf'};

Map<String, Object?> _withProperties(Map<String, Object?> schema) => {
  for (final MapEntry(:key, :value) in schema.entries)
    key: switch (value) {
      final Map<String, Object?> properties when key == 'properties' =>
        properties.map((name, schema) => MapEntry(name, _subschema(schema))),
      _ when _schemaKeys.contains(key) => _subschema(value),
      final List<Object?> schemas when _schemaListKeys.contains(key) => [
        for (final item in schemas) _subschema(item),
      ],
      _ => value,
    },
  if (schema['type'] == 'object' && !schema.containsKey('properties'))
    'properties': <String, Object?>{},
};

Object? _subschema(Object? value) =>
    value is Map<String, Object?> ? _withProperties(value) : value;
