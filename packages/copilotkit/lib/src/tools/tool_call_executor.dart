import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/client_tool.dart';
import 'package:copilotkit/src/tools/models/fallback_tool_result.dart';
import 'package:copilotkit/src/tools/models/invalid_tool_arguments.dart';
import 'package:copilotkit/src/tools/models/tool_call_outcome.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:copilotkit/src/tools/tool_responses.dart';

/// Produces the result of a client tool for one call of the agent.
class const ToolCallExecutor() {
  /// Creates an executor.
  this;

  /// Whether the arguments of [call] match the parameters of [tool].
  bool accepts(ClientTool<Object?> tool, ToolCallView call) =>
      tool.parameters.safeParse(call.args) is Ok;

  /// Produces the result of [call] for [tool] within the turn [signal]
  /// belongs to: runs the handler of a [FrontendTool], or waits in
  /// [responses] for the user to answer a [HumanInTheLoopTool].
  ///
  /// Arguments that don't match [ClientTool.parameters] never reach the
  /// tool: the result lists the problems so the agent can fix them, and
  /// they are logged rather than reported, since the agent is at fault. A
  /// decoder or handler that throws gives a generic result and the error,
  /// since the app is at fault. Never throws.
  Future<ToolCallOutcome> call(
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
        final result = InvalidToolArguments(error).message;
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
}
