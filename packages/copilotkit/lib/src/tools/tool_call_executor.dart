import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:copilotkit/src/json/json.dart';
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

  /// Whether the arguments of [call] match the parameters of [tool].
  bool accepts(ClientTool<Object?> tool, ToolCallView call) =>
      tool.parameters.safeParse(call.args.toJson()) is Ok;

  /// Produces the result of [call] for [tool] within the turn [signal]
  /// belongs to: runs the handler of a [FrontendTool], or waits in
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
    final JsonObject args;
    switch (tool.parameters.safeParse(call.args.toJson())) {
      case Ok(:final value):
        args = JsonObject(value ?? const {});
      case Fail(:final error):
        final result = error.invalidArgumentsResult;
        developer.log(
          'Invalid arguments for tool "${call.name}":\n$result',
          name: 'copilotkit',
          level: 900, // WARNING
          error: error,
        );
        return ToolCallOutcome(result: result, invalidArguments: true);
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
    JsonObject args,
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
}

extension on SchemaError {
  static const _invalidArgumentsSummary =
      "The tool didn't run: its arguments don't match its parameters. "
      'Fix them and call it again.';

  /// The root of a JSON Pointer path, e.g. `#` or the `#/` in `#/city`.
  static final _rootPointer = RegExp('^#/?');

  /// Ack's prefix on constraint errors; the path already says what failed.
  static const _constraintsPrefix = 'Constraints not met: ';

  /// The result of a call whose arguments failed with this error: a summary,
  /// then one problem per line, by argument path.
  String get invalidArgumentsResult => [
    _invalidArgumentsSummary,
    for (final problem in problems) '- ${problem.description}',
  ].join('\n');

  /// The innermost errors under this one.
  Iterable<SchemaError> get problems => switch (this) {
    SchemaNestedError(:final errors) when errors.isNotEmpty => errors.expand(
      (error) => error.problems,
    ),
    final error => [error],
  };

  /// This error as `path: message`, e.g. `unit.step: Expected integer, got
  /// string.`; root errors have no path.
  String get description {
    final path = this.path.replaceFirst(_rootPointer, '').replaceAll('/', '.');
    var message = this.message.replaceFirst(_constraintsPrefix, '');
    if (!message.endsWith('.')) message = '$message.';
    return path.isEmpty ? message : '$path: $message';
  }
}
