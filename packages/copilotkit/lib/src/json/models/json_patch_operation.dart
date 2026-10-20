import 'package:equatable/equatable.dart';

/// One operation of an RFC 6902 JSON Patch.
///
/// Paths are RFC 6901 JSON Pointers, e.g. `/items/0`; `''` is the whole
/// document.
sealed class JsonPatchOperation extends Equatable {
  const new();

  /// Parses one operation of a JSON Patch document.
  ///
  /// Throws a [FormatException] when the op is unknown or a pointer it needs
  /// is missing.
  factory fromJson(Map<String, Object?> json) {
    String pointer(String key) => switch (json[key]) {
      final String pointer => pointer,
      _ => throw FormatException('Missing JSON Patch $key'),
    };

    return switch (json['op']) {
      'add' => JsonPatchAdd(path: pointer('path'), value: json['value']),
      'remove' => JsonPatchRemove(path: pointer('path')),
      'replace' => JsonPatchReplace(
        path: pointer('path'),
        value: json['value'],
      ),
      'move' => JsonPatchMove(from: pointer('from'), path: pointer('path')),
      'copy' => JsonPatchCopy(from: pointer('from'), path: pointer('path')),
      'test' => JsonPatchTest(path: pointer('path'), value: json['value']),
      final op => throw FormatException('Unknown JSON Patch op: $op'),
    };
  }

  /// Returns this operation as an RFC 6902 operation object.
  Map<String, Object?> toJson();
}

/// Adds [value] at [path]: sets an object member, or inserts into an array
/// (`-` appends).
final class const JsonPatchAdd({
  /// Where to add the value.
  required final String path,

  /// The JSON value to add.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that adds [value] at [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'add', 'path': path, 'value': value};

  @override
  List<Object?> get props => [path, value];
}

/// Removes the value at [path].
final class const JsonPatchRemove({
  /// Where the value to remove is.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that removes the value at [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'remove', 'path': path};

  @override
  List<Object?> get props => [path];
}

/// Replaces the value at [path] with [value].
final class const JsonPatchReplace({
  /// Where the value to replace is.
  required final String path,

  /// The JSON value to put there.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that replaces the value at [path] with [value].
  this;

  @override
  Map<String, Object?> toJson() => {
    'op': 'replace',
    'path': path,
    'value': value,
  };

  @override
  List<Object?> get props => [path, value];
}

/// Moves the value at [from] to [path].
final class const JsonPatchMove({
  /// Where the value to move is.
  required final String from,

  /// Where to move it.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that moves the value at [from] to [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'move', 'from': from, 'path': path};

  @override
  List<Object?> get props => [from, path];
}

/// Copies the value at [from] to [path].
final class const JsonPatchCopy({
  /// Where the value to copy is.
  required final String from,

  /// Where to copy it.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that copies the value at [from] to [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'copy', 'from': from, 'path': path};

  @override
  List<Object?> get props => [from, path];
}

/// Checks that the value at [path] equals [value]; the patch fails if not.
final class const JsonPatchTest({
  /// Where the value to check is.
  required final String path,

  /// The JSON value it must equal.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that checks the value at [path] equals [value].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'test', 'path': path, 'value': value};

  @override
  List<Object?> get props => [path, value];
}
