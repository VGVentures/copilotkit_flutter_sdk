import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/active_run.dart';
import 'package:copilotkit/src/client/models/run_result.dart';
import 'package:copilotkit/src/client/run_input_builder.dart';
import 'package:copilotkit/src/client/turn.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Sends one run of an agent to the runtime and applies its events to the
/// agent.
class const RunStreamer({
  /// Sends the runs to the runtime.
  required final AgentTransport _transport,

  /// The client tools sent with every run.
  required final ToolRegistry _tools,

  /// The app data sent with every run.
  required final AgentContextStore _context,

  /// Receives errors from runs and the transport.
  required final CopilotErrorHandler _onError,

  /// Builds the headers of each run, e.g. for auth.
  final HeadersBuilder? _headers,

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final Map<String, Object?>? _properties,

  /// Builds the input of each run.
  final RunInputBuilder _inputBuilder = const RunInputBuilder(),
}) {
  /// Creates a streamer that sends runs through the given transport.
  this;

  /// Streams one run of the agent of [turn] and returns how it ended.
  ///
  /// While the run streams, `Turn.run` holds it so a stop can cancel it; it
  /// is cleared once the run ends. Never throws: a failure is recorded on
  /// the agent and goes to the error handler.
  Future<RunResult> call(Turn turn) async {
    final agent = turn.agent;
    final RunAgentInput input;
    final Map<String, String> headers;
    final Stream<BaseEvent> events;
    try {
      input = _inputBuilder(
        agent: agent.state,
        tools: _tools.tools.values,
        context: _context.entries,
        properties: _properties,
      );
      headers = await _headers?.call() ?? const {};
      // Stopped or closed while the headers were being built.
      if (turn.signal.isCancelled) return RunResult.stopped;
      events = _transport.run(
        agentId: agent.state.agentId,
        input: input,
        headers: headers,
      );
    } on Object catch (error, stackTrace) {
      _fail(agent, error, stackTrace);
      return RunResult.failed;
    }

    // The stream ending and a stop can race; only the first completes it.
    final streamDone = Completer<void>();
    void finish() {
      if (!streamDone.isCompleted) streamDone.complete();
    }

    // Whether the runtime sent RUN_FINISHED or RUN_ERROR.
    var ended = false;
    turn.run = ActiveRun(
      runId: input.runId,
      headers: headers,
      // Cancelled on error (cancelOnError), by a stop and by close().
      subscription: events.listen(
        (event) {
          if (event is RunFinishedEvent || event is RunErrorEvent) {
            ended = true;
          }
          agent.apply(event);
          if (event case RunErrorEvent(:final message, :final code)) {
            _onError(
              RunError(message: message, code: code),
              StackTrace.current,
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _fail(agent, error, stackTrace);
          finish();
        },
        onDone: () {
          if (!ended) {
            _fail(
              agent,
              StateError('The connection closed before the run finished.'),
              StackTrace.current,
            );
          }
          finish();
        },
        cancelOnError: true,
      ),
    );
    await Future.any([streamDone.future, turn.signal.whenCancelled]);
    if (turn.signal.isCancelled) return RunResult.stopped;
    turn.run = null;
    return agent.state.error == null ? RunResult.finished : RunResult.failed;
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.fail(error);
    _onError(error, stackTrace);
  }
}
