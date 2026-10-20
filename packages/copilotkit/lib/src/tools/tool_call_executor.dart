import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:copilotkit/src/tools/models/fallback_tool_result.dart';
import 'package:copilotkit/src/tools/models/tool_call_outcome.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';

/// Runs the handler of a frontend tool for one call of the agent.
class const ToolCallExecutor() {
  /// Creates an executor.
  this;

  /// The root of a JSON Pointer path, e.g. `#` or the `#/` in `#/city`.
  static final _rootPointer = RegExp('^#/?');

  /// Ack's prefix on constraint errors; the path already says what failed.
  static const _constraintsPrefix = 'Constraints not met: ';

  static const _invalidArgumentsSummary =
      "The tool didn't run: its arguments don't match its parameters. "
      'Fix them and call it again.';

  /// Runs the handler of [tool] for [call] with the turn's [signal].
  ///
  /// Arguments that don't match `FrontendTool.parameters` never reach the
  /// handler: the result lists the problems so the agent can fix them, and
  /// they are logged rather than reported, since the agent is at fault. A
  /// decoder or handler that throws gives a generic result and the error,
  /// since the app is at fault. Never throws.
  Future<ToolCallOutcome> execute(
    FrontendTool<Object?> tool,
    ToolCallView call,
    CancellationSignal signal,
  ) async {
    final JsonObject args;
    switch (tool.parameters.safeParse(call.args.toJson())) {
      case Ok(:final value):
        args = JsonObject(value ?? const {});
      case Fail(:final error):
        final result = _invalidArgumentsResult(error);
        developer.log(
          'Invalid arguments for tool "${call.name}":\n$result',
          name: 'copilotkit',
          level: 900, // WARNING
          error: error,
        );
        return ToolCallOutcome(result: result);
    }
    try {
      return ToolCallOutcome(result: await tool.run(args, signal: signal));
    } on Object catch (error, stackTrace) {
      return ToolCallOutcome(
        result: FallbackToolResult.handlerError.message,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Lists one problem of [error] per line, by argument path.
  String _invalidArgumentsResult(SchemaError error) => [
    _invalidArgumentsSummary,
    for (final problem in _problems(error)) '- ${_describe(problem)}',
  ].join('\n');

  /// The innermost errors under [error].
  Iterable<SchemaError> _problems(SchemaError error) => switch (error) {
    SchemaNestedError(:final errors) when errors.isNotEmpty => errors.expand(
      _problems,
    ),
    _ => [error],
  };

  /// Describes [error] as `path: message`, e.g. `unit.step: Expected
  /// integer, got string.`; root errors have no path.
  String _describe(SchemaError error) {
    final path = error.path.replaceFirst(_rootPointer, '').replaceAll('/', '.');
    var message = error.message.replaceFirst(_constraintsPrefix, '');
    if (!message.endsWith('.')) message = '$message.';
    return path.isEmpty ? message : '$path: $message';
  }
}
