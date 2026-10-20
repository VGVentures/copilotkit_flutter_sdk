/// Normalizes JSON Schemas so that providers accept them.
class const JsonSchemaNormalizer() {
  /// Creates a normalizer.
  this;

  /// Returns a copy of [schema] where every object schema has `properties`.
  ///
  /// Some schema builders omit `properties` on empty objects, at any depth,
  /// and some providers reject object schemas without it, so every object
  /// schema gets an empty `properties` map when it has none. [schema] is
  /// never mutated.
  Map<String, Object?> normalize(Map<String, Object?> schema) => {
    for (final MapEntry(:key, :value) in schema.entries)
      key: switch (value) {
        final Map<String, Object?> properties when key == 'properties' =>
          properties.map((name, schema) => MapEntry(name, _subschema(schema))),
        _ when _SubschemaKey.values.asNameMap().containsKey(key) => _subschema(
          value,
        ),
        final List<Object?> schemas
            when _SubschemaListKey.values.asNameMap().containsKey(key) =>
          [for (final item in schemas) _subschema(item)],
        _ => value,
      },
    if (schema['type'] == 'object' && !schema.containsKey('properties'))
      'properties': <String, Object?>{},
  };

  Object? _subschema(Object? value) =>
      value is Map<String, Object?> ? normalize(value) : value;
}

/// JSON Schema keys whose value is a subschema.
enum _SubschemaKey { items, additionalProperties, not }

/// JSON Schema keys whose value is a list of subschemas.
enum _SubschemaListKey { anyOf, oneOf, allOf }
