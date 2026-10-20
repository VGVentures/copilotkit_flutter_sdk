/// Applies RFC 6902 JSON Patches to JSON objects.
class const JsonPatcher() {
  /// Creates a patcher.
  this;

  /// Applies [operations] to [document] and returns the result.
  ///
  /// Each operation is an RFC 6902 operation object, e.g.
  /// `{'op': 'add', 'path': '/items/-', 'value': 1}`, whose paths are RFC 6901
  /// JSON Pointers; `''` is the whole document. [document] is never mutated.
  ///
  /// Throws a [FormatException] when an op is unknown, a pointer it needs is
  /// missing or malformed, a path doesn't exist, a `test` fails, or the
  /// result isn't a JSON object.
  Map<String, Object?> apply(
    Map<String, Object?> document,
    List<Map<String, Object?>> operations,
  ) {
    var result = _deepCopy(document);
    for (final operation in operations) {
      result = _apply(result, operation);
    }
    return switch (result) {
      final Map<String, Object?> object => object,
      _ => throw FormatException(
        'JSON Patch replaced the root with a non-object: $result',
      ),
    };
  }

  Object? _apply(Object? document, Map<String, Object?> operation) {
    final value = operation['value'];
    switch (_operationOf(operation)) {
      case _Operation.add:
        return _add(document, _pointer(operation, 'path'), _deepCopy(value));
      case _Operation.remove:
        _remove(document, _pointer(operation, 'path'));
        return document;
      case _Operation.replace:
        final tokens = _pointer(operation, 'path');
        if (tokens.isEmpty) return _deepCopy(value);
        _remove(document, tokens);
        return _add(document, tokens, _deepCopy(value));
      case _Operation.move:
        final fromTokens = _pointer(operation, 'from');
        final moved = _get(document, fromTokens);
        _remove(document, fromTokens);
        return _add(document, _pointer(operation, 'path'), moved);
      case _Operation.copy:
        final copied = _deepCopy(_get(document, _pointer(operation, 'from')));
        return _add(document, _pointer(operation, 'path'), copied);
      case _Operation.test:
        if (!_deepEquals(_get(document, _pointer(operation, 'path')), value)) {
          throw FormatException(
            'JSON Patch test failed at ${operation['path']}',
          );
        }
        return document;
    }
  }

  _Operation _operationOf(Map<String, Object?> operation) {
    final op = operation['op'];
    return switch (_Operation.values.asNameMap()[op]) {
      final _Operation operation => operation,
      null => throw FormatException('Unknown JSON Patch op: $op'),
    };
  }

  /// Parses the RFC 6901 pointer under [key] in [operation] into reference
  /// tokens.
  List<String> _pointer(Map<String, Object?> operation, String key) {
    final pointer = switch (operation[key]) {
      final String pointer => pointer,
      _ => throw FormatException('Missing JSON Patch $key'),
    };
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
        Map<String, Object?>() when current.containsKey(token) =>
          current[token],
        List<Object?>() => current[_index(current, token, current.length - 1)],
        _ => throw FormatException('JSON Patch path not found: /$token'),
      };
    }
    return current;
  }

  /// The container that holds the value at the non-empty [path], and the
  /// last token, which names that value in it.
  ({Object? parent, String token}) _parentOf(
    Object? document,
    List<String> path,
  ) => (
    parent: _get(document, path.sublist(0, path.length - 1)),
    token: path.last,
  );

  Object? _add(Object? document, List<String> path, Object? value) {
    if (path.isEmpty) return value;
    final (:parent, :token) = _parentOf(document, path);
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
    final (:parent, :token) = _parentOf(document, path);
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
}

/// The operations of an RFC 6902 JSON Patch, named after their `op`.
enum _Operation { add, remove, replace, move, copy, test }
