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
}

/// Adds [value] at [path]: sets an object member, or inserts into an array
/// (`-` appends).
final class const JsonPatchAdd({
  /// The JSON Pointer to add the value at.
  required final String path,

  /// The JSON value to add.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that adds [value] at [path].
  this;

  @override
  List<Object?> get props => [path, value];
}

/// Removes the value at [path].
final class const JsonPatchRemove({
  /// The JSON Pointer of the value to remove.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that removes the value at [path].
  this;

  @override
  List<Object?> get props => [path];
}

/// Replaces the value at [path] with [value].
final class const JsonPatchReplace({
  /// The JSON Pointer of the value to replace.
  required final String path,

  /// The JSON value to put there.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that replaces the value at [path] with [value].
  this;

  @override
  List<Object?> get props => [path, value];
}

/// Moves the value at [from] to [path].
final class const JsonPatchMove({
  /// The JSON Pointer of the value to move.
  required final String from,

  /// The JSON Pointer to move the value to.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that moves the value at [from] to [path].
  this;

  @override
  List<Object?> get props => [from, path];
}

/// Copies the value at [from] to [path].
final class const JsonPatchCopy({
  /// The JSON Pointer of the value to copy.
  required final String from,

  /// The JSON Pointer to copy the value to.
  required final String path,
}) extends JsonPatchOperation {
  /// Creates an operation that copies the value at [from] to [path].
  this;

  @override
  List<Object?> get props => [from, path];
}

/// Checks that the value at [path] equals [value]; the patch fails if not.
final class const JsonPatchTest({
  /// The JSON Pointer of the value to check.
  required final String path,

  /// The JSON value it must equal.
  required final Object? value,
}) extends JsonPatchOperation {
  /// Creates an operation that checks the value at [path] equals [value].
  this;

  @override
  List<Object?> get props => [path, value];
}
