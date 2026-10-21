/// @docImport 'package:copilotkit/src/client/copilot_kit_client.dart';
library;

import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/active_run.dart';
import 'package:copilotkit/src/tools/tools.dart';

/// The turn in flight of one agent: the runs and tool calls between
/// [CopilotKitClient.runAgent] and the moment the agent stops calling tools.
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
