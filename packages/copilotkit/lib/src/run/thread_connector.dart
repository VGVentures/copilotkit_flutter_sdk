import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/run/active_run.dart';
import 'package:copilotkit/src/run/run_streamer.dart';
import 'package:copilotkit/src/run/turn.dart';
import 'package:copilotkit/src/transport/transport.dart';
import 'package:uuid/uuid.dart';

/// Rebuilds the conversation of an agent from the runtime's replay of its
/// thread.
class const ThreadConnector({
  /// Opens the replays.
  required final AgentTransport _transport,

  /// Receives errors from the transport.
  required final CopilotErrorHandler _onError,

  /// Builds the headers of each connection, e.g. for auth.
  final HeadersBuilder? _headers,

  /// Generates the id of each connection.
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a connector that opens replays through the given transport.
  this;

  /// Connects the agent of [turn] to its thread and applies the replayed
  /// events to it.
  ///
  /// Starts from an empty conversation and shared state, as a snapshot would,
  /// so what the runtime replays is the whole conversation. The replay also
  /// adds the messages that the `RUN_STARTED` events of the history carry,
  /// which is where the runtime keeps the user's messages. A runtime with no
  /// history for the thread sends nothing, and the agent stays empty. When
  /// a run of the thread is still going, its events keep arriving until it
  /// ends.
  ///
  /// While the replay streams, the turn holds it so a stop can cancel it.
  /// Never throws: a failure is recorded on the agent and goes to the error
  /// handler. A replayed `RUN_ERROR` is recorded on the agent but not
  /// reported: it may belong to a run of the past.
  Future<void> call(Turn turn) async {
    final agent = turn.agent;
    final Map<String, String> headers;
    final Stream<BaseEvent> events;
    try {
      headers = await _headers?.call() ?? const {};
      // Stopped or closed while the headers were being built.
      if (turn.signal.isCancelled) return;
      agent
        ..setMessages(const [])
        ..setSharedState(null);
      events = _transport.connect(
        agentId: agent.state.agentId,
        input: RunAgentInput(
          threadId: agent.state.threadId,
          runId: _uuid.v4(),
          state: const <String, Object?>{},
          messages: const [],
          tools: const [],
          context: const [],
        ),
        headers: headers,
      );
    } on Object catch (error, stackTrace) {
      _fail(agent, error, stackTrace);
      return;
    }

    // The stream ending and a stop can race; only the first completes it.
    final streamDone = Completer<void>();
    void finish() {
      if (!streamDone.isCompleted) streamDone.complete();
    }

    // The runs of the replay that started and have not ended.
    var open = 0;
    turn.attach(
      ActiveRun(
        headers: headers,
        // Cancelled on error (cancelOnError), by a stop and by close().
        subscription: events.listen(
          (event) {
            switch (event) {
              case RunStartedEvent(:final input):
                open++;
                if (input != null) {
                  agent.setMessages(
                    agent.state.messagesWithMissing(input.messages),
                  );
                }
              case RunFinishedEvent() || RunErrorEvent():
                if (open > 0) open--;
              default:
            }
            agent.apply(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            _fail(agent, error, stackTrace);
            finish();
          },
          onDone: () {
            if (open > 0) {
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
      ),
    );
    await Future.any([streamDone.future, turn.signal.whenCancelled]);
    if (!turn.signal.isCancelled) turn.detach();
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.fail(error);
    _onError(error, stackTrace);
  }
}
