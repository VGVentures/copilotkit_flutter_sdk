import 'package:copilotkit/src/json/models/json_patch_operation.dart';

/// Applies RFC 6902 JSON Patches.
class const JsonPatcher() {
  /// Creates a patcher.
  this;

  /// Applies [operations] to [document] and returns the result.
  ///
  /// [document] is never mutated. Throws a [FormatException] when a pointer
  /// is malformed, a path doesn't exist, or a [JsonPatchTest] fails.
  Object? apply(Object? document, List<JsonPatchOperation> operations) {
    var result = document.deepCopy();
    for (final operation in operations) {
      result = _apply(result, operation);
    }
    return result;
  }

  Object? _apply(Object? document, JsonPatchOperation operation) {
    switch (operation) {
      case JsonPatchAdd(:final path, :final value):
        return _add(document, path.pointerTokens, value.deepCopy());
      case JsonPatchRemove(:final path):
        _remove(document, path.pointerTokens);
        return document;
      case JsonPatchReplace(:final path, :final value):
        final tokens = path.pointerTokens;
        if (tokens.isEmpty) return value.deepCopy();
        _remove(document, tokens);
        return _add(document, tokens, value.deepCopy());
      case JsonPatchMove(:final from, :final path):
        final fromTokens = from.pointerTokens;
        final value = _get(document, fromTokens);
        _remove(document, fromTokens);
        return _add(document, path.pointerTokens, value);
      case JsonPatchCopy(:final from, :final path):
        final value = _get(document, from.pointerTokens).deepCopy();
        return _add(document, path.pointerTokens, value);
      case JsonPatchTest(:final path, :final value):
        if (!_get(document, path.pointerTokens).deepEquals(value)) {
          throw FormatException('JSON Patch test failed at $path');
        }
        return document;
    }
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
}

extension on String {
  /// This RFC 6901 JSON Pointer parsed into reference tokens.
  List<String> get pointerTokens {
    if (isEmpty) return const [];
    if (!startsWith('/')) {
      throw FormatException('Invalid JSON Pointer: $this');
    }
    return [
      for (final token in substring(1).split('/'))
        token.replaceAll('~1', '/').replaceAll('~0', '~'),
    ];
  }
}

extension on Object? {
  /// A copy of this JSON value that shares no map or list with it.
  Object? deepCopy() => switch (this) {
    final Map<String, Object?> map => {
      for (final entry in map.entries) entry.key: entry.value.deepCopy(),
    },
    final List<Object?> list => [for (final item in list) item.deepCopy()],
    final value => value,
  };

  /// Whether this JSON value and [other] hold the same data.
  bool deepEquals(Object? other) {
    final value = this;
    if (value is Map<String, Object?> && other is Map<String, Object?>) {
      return value.length == other.length &&
          value.entries.every(
            (e) => other.containsKey(e.key) && e.value.deepEquals(other[e.key]),
          );
    }
    if (value is List<Object?> && other is List<Object?>) {
      if (value.length != other.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (!value[i].deepEquals(other[i])) return false;
      }
      return true;
    }
    return value == other;
  }
}
