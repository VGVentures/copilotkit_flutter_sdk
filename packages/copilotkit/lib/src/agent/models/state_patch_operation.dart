/// @docImport 'package:copilotkit/src/agent/copilot_agent.dart';
library;

import 'package:equatable/equatable.dart';

/// One edit of the shared state, applied with
/// [CopilotAgent.patchSharedState].
///
/// The operations are those of an RFC 6902 JSON Patch, the format of a
/// `STATE_DELTA`. Paths are RFC 6901 JSON Pointers, e.g. `/items/0`; `''` is
/// the whole state.
sealed class StatePatchOperation extends Equatable {
  const new();

  /// Returns this operation as an RFC 6902 operation object, e.g.
  /// `{'op': 'add', 'path': '/items/-', 'value': 1}`.
  Map<String, Object?> toJson();
}

/// Adds [value] at [path]: sets an object member, or inserts into an array
/// (`-` appends).
final class const StatePatchAdd({
  /// Where to add the value.
  required final String path,

  /// The JSON value to add.
  required final Object? value,
}) extends StatePatchOperation {
  /// Creates an operation that adds [value] at [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'add', 'path': path, 'value': value};

  @override
  List<Object?> get props => [path, value];
}

/// Removes the value at [path].
final class const StatePatchRemove({
  /// Where the value to remove is.
  required final String path,
}) extends StatePatchOperation {
  /// Creates an operation that removes the value at [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'remove', 'path': path};

  @override
  List<Object?> get props => [path];
}

/// Replaces the value at [path] with [value].
final class const StatePatchReplace({
  /// Where the value to replace is.
  required final String path,

  /// The JSON value to put there.
  required final Object? value,
}) extends StatePatchOperation {
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
final class const StatePatchMove({
  /// Where the value to move is.
  required final String from,

  /// Where to move it.
  required final String path,
}) extends StatePatchOperation {
  /// Creates an operation that moves the value at [from] to [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'move', 'from': from, 'path': path};

  @override
  List<Object?> get props => [from, path];
}

/// Copies the value at [from] to [path].
final class const StatePatchCopy({
  /// Where the value to copy is.
  required final String from,

  /// Where to copy it.
  required final String path,
}) extends StatePatchOperation {
  /// Creates an operation that copies the value at [from] to [path].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'copy', 'from': from, 'path': path};

  @override
  List<Object?> get props => [from, path];
}

/// Checks that the value at [path] equals [value]; the patch fails if not.
final class const StatePatchTest({
  /// Where the value to check is.
  required final String path,

  /// The JSON value it must equal.
  required final Object? value,
}) extends StatePatchOperation {
  /// Creates an operation that checks the value at [path] equals [value].
  this;

  @override
  Map<String, Object?> toJson() => {'op': 'test', 'path': path, 'value': value};

  @override
  List<Object?> get props => [path, value];
}
