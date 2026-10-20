import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/tools/tools.dart';

/// The turn in flight of one agent: the runs and tool calls between
/// `CopilotKitClient.runAgent` and the moment the agent stops calling tools.
///
/// The run being streamed comes and goes during the turn, so this is
/// mutable: a documented exception to the immutability rule.
class Turn(
  /// The agent the turn runs.
  final CopilotAgent agent,
) {
  /// Creates a turn of [agent].
  this;

  /// Cancelled when the turn is stopped or the runner is closed.
  final CancellationSignal signal = CancellationSignal();

  /// The run being streamed, or `null` between runs.
  ActiveRun? run;
}

/// A run being streamed: what a stop request needs, and the subscription to
/// cancel.
class const ActiveRun({
  /// The id of the run, sent with a stop request.
  required final String runId,

  /// The headers the run was sent with, sent again with a stop request.
  required final Map<String, String> headers,

  // Cancelled by the runner on stop and close.
  // ignore: cancel_subscriptions
  /// The run's events. Cancelled by a stop or a close, never by the
  /// streamer.
  required final StreamSubscription<BaseEvent> subscription,
}) {
  /// Creates the handle of a run being streamed.
  this;
}
