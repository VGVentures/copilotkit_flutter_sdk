/// Applies an RFC 6902 JSON Patch to [document] and returns the result.
///
/// [document] is never mutated. Throws a [FormatException] when an operation
/// is malformed, a path doesn't exist, or a `test` operation fails.
Object? applyJsonPatch(
  Object? document,
  List<Map<String, Object?>> operations,
) {
  var result = _deepCopy(document);
  for (final operation in operations) {
    result = _apply(result, operation);
  }
  return result;
}

Object? _apply(Object? document, Map<String, Object?> operation) {
  final path = _pointer(operation, 'path');
  switch (operation['op']) {
    case 'add':
      return _add(document, path, _deepCopy(operation['value']));
    case 'remove':
      _remove(document, path);
      return document;
    case 'replace':
      if (path.isEmpty) return _deepCopy(operation['value']);
      _remove(document, path);
      return _add(document, path, _deepCopy(operation['value']));
    case 'move':
      final from = _pointer(operation, 'from');
      final value = _get(document, from);
      _remove(document, from);
      return _add(document, path, value);
    case 'copy':
      final value = _deepCopy(_get(document, _pointer(operation, 'from')));
      return _add(document, path, value);
    case 'test':
      if (!_deepEquals(_get(document, path), operation['value'])) {
        throw FormatException('JSON Patch test failed at ${operation['path']}');
      }
      return document;
    default:
      throw FormatException('Unknown JSON Patch op: ${operation['op']}');
  }
}

/// Parses the RFC 6901 pointer in [operation][key] into reference tokens.
List<String> _pointer(Map<String, Object?> operation, String key) {
  final pointer = operation[key];
  if (pointer is! String) throw FormatException('Missing JSON Patch $key');
  if (pointer.isEmpty) return const [];
  if (!pointer.startsWith('/')) {
    throw FormatException('Invalid JSON Pointer: $pointer');
  }
  return [
    for (final token in pointer.substring(1).split('/'))
      token.replaceAll('~1', '/').replaceAll('~0', '~'),
  ];
}

Object? _get(Object? document, List<String> path) {
  var current = document;
  for (final token in path) {
    current = switch (current) {
      Map<String, Object?>() when current.containsKey(token) => current[token],
      List<Object?>() => current[_index(current, token, current.length - 1)],
      _ => throw FormatException('JSON Patch path not found: /$token'),
    };
  }
  return current;
}

Object? _add(Object? document, List<String> path, Object? value) {
  if (path.isEmpty) return value;
  final parent = _get(document, path.sublist(0, path.length - 1));
  final token = path.last;
  switch (parent) {
    case Map<String, Object?>():
      parent[token] = value;
    case List<Object?>():
      if (token == '-') {
        parent.add(value);
      } else {
        parent.insert(_index(parent, token, parent.length), value);
      }
    default:
      throw FormatException('JSON Patch parent is not a container: /$token');
  }
  return document;
}

void _remove(Object? document, List<String> path) {
  if (path.isEmpty) throw const FormatException('Cannot remove the root');
  final parent = _get(document, path.sublist(0, path.length - 1));
  final token = path.last;
  switch (parent) {
    case Map<String, Object?>() when parent.containsKey(token):
      parent.remove(token);
    case List<Object?>():
      parent.removeAt(_index(parent, token, parent.length - 1));
    default:
      throw FormatException('JSON Patch path not found: /$token');
  }
}

/// Parses an array index token, allowing values up to [max].
int _index(List<Object?> list, String token, int max) {
  final index = int.tryParse(token);
  if (index == null || index < 0 || index > max) {
    throw FormatException('Invalid JSON Patch array index: $token');
  }
  return index;
}

Object? _deepCopy(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final entry in value.entries) entry.key: _deepCopy(entry.value),
  },
  List<Object?>() => [for (final item in value) _deepCopy(item)],
  _ => value,
};

bool _deepEquals(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return a.length == b.length &&
        a.entries.every(
          (e) => b.containsKey(e.key) && _deepEquals(e.value, b[e.key]),
        );
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
