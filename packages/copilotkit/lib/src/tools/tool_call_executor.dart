import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/client_tool.dart';
import 'package:copilotkit/src/tools/models/fallback_tool_result.dart';
import 'package:copilotkit/src/tools/models/tool_call_outcome.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:copilotkit/src/tools/tool_responses.dart';

/// Produces the result of a client tool for one call of the agent.
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

  /// Whether the arguments of [call] match the parameters of [tool].
  bool accepts(ClientTool<Object?> tool, ToolCallView call) =>
      tool.parameters.safeParse(call.args) is Ok;

  /// Produces the result of [call] for [tool] until the call's [signal] is
  /// cancelled: runs the handler of a [FrontendTool], or waits in
  /// [responses] for the user to answer a [HumanInTheLoopTool].
  ///
  /// Arguments that don't match [ClientTool.parameters] never reach the
  /// tool: the result lists the problems so the agent can fix them, and
  /// they are logged rather than reported, since the agent is at fault. A
  /// decoder or handler that throws gives a generic result and the error,
  /// since the app is at fault. Never throws.
  Future<ToolCallOutcome> execute(
    ClientTool<Object?> tool,
    ToolCallView call,
    CancellationSignal signal, {
    required ToolResponses responses,
  }) async {
    final Map<String, Object?> args;
    switch (tool.parameters.safeParse(call.args)) {
      case Ok(:final value):
        args = Map.unmodifiable(value ?? const <String, Object?>{});
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
    return switch (tool) {
      FrontendTool() => await _run(tool, args, signal),
      HumanInTheLoopTool() => ToolCallOutcome(
        result: await responses.wait(call.id, signal),
      ),
    };
  }

  Future<ToolCallOutcome> _run(
    FrontendTool<Object?> tool,
    Map<String, Object?> args,
    CancellationSignal signal,
  ) async {
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
