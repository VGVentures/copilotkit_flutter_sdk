import 'package:ack/ack.dart';
import 'package:equatable/equatable.dart';

/// Arguments of a tool call that don't match the tool's parameters.
///
/// Its [message] is the result sent to the agent instead of running the
/// tool, so the agent can fix the arguments and call it again.
class const InvalidToolArguments(
  /// What the validation of the arguments reported.
  final SchemaError error,
) extends Equatable {
  /// Creates the invalid arguments that [error] describes.
  this;

  /// The root of a JSON Pointer path, e.g. `#` or the `#/` in `#/city`.
  static final _rootPointer = RegExp('^#/?');

  /// Ack's prefix on constraint errors; the path already says what failed.
  static const _constraintsPrefix = 'Constraints not met: ';

  static const _summary =
      "The tool didn't run: its arguments don't match its parameters. "
      'Fix them and call it again.';

  /// The innermost errors under [error], one per problem.
  Iterable<SchemaError> get problems => _innermost(error);

  /// The result sent to the agent: a summary, then one problem per line as
  /// `path: message`, e.g. `unit.step: Expected integer, got string.`.
  /// Problems at the root have no path.
  String get message => [
    _summary,
    for (final problem in problems) '- ${_describe(problem)}',
  ].join('\n');

  @override
  List<Object?> get props => [message];

  Iterable<SchemaError> _innermost(SchemaError error) => switch (error) {
    SchemaNestedError(:final errors) when errors.isNotEmpty => errors.expand(
      _innermost,
    ),
    _ => [error],
  };

  String _describe(SchemaError problem) {
    final path = problem.path
        .replaceFirst(_rootPointer, '')
        .replaceAll('/', '.');
    var text = problem.message.replaceFirst(_constraintsPrefix, '');
    if (!text.endsWith('.')) text = '$text.';
    return path.isEmpty ? text : '$path: $text';
  }
}
