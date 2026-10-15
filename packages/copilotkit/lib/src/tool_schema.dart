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

/// The tool result sent instead of running a handler whose arguments failed
/// validation with [error].
///
/// Lists one problem per line, by argument path, so the agent can fix the
/// arguments and call the tool again.
String invalidArgumentsResult(SchemaError error) => [
  _invalidArgumentsSummary,
  for (final problem in _problems(error)) '- ${_describe(problem)}',
].join('\n');

const _invalidArgumentsSummary =
    "The tool didn't run: its arguments don't match its parameters. "
    'Fix them and call it again.';

/// The innermost errors under [error].
Iterable<SchemaError> _problems(SchemaError error) => switch (error) {
  SchemaNestedError(:final errors) when errors.isNotEmpty => errors.expand(
    _problems,
  ),
  _ => [error],
};

/// Describes [error] as `path: message`, e.g. `unit.step: Expected integer,
/// got string.`; root errors have no path.
String _describe(SchemaError error) {
  final path = error.path.replaceFirst(_rootPointer, '').replaceAll('/', '.');
  var message = error.message.replaceFirst(_constraintsPrefix, '');
  if (!message.endsWith('.')) message = '$message.';
  return path.isEmpty ? message : '$path: $message';
}

/// The root of a JSON Pointer path, e.g. `#` or the `#/` in `#/city`.
final _rootPointer = RegExp('^#/?');

/// Ack's prefix on constraint errors; the path already says what failed.
const _constraintsPrefix = 'Constraints not met: ';
