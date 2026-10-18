import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/tools/cancellation_controller.dart';
import 'package:equatable/equatable.dart';

/// One `AgentRunRequested` turn: the stream runs plus the tool handlers
/// between them, until the agent stops calling tools or the turn is stopped.
class const TurnState({
  /// Cancels the turn's signal when the turn is stopped or the client
  /// closes. Tool handlers receive the signal; `isCancelled` is the turn's
  /// "stopped" flag.
  required final CancellationController controller,

  /// The run whose stream is open, or `null` between runs.
  final RunState? run,
}) extends Equatable {
  /// Creates the state of a turn.
  this;

  /// Returns a copy with [run] replaced; `run: () => null` clears it.
  TurnState copyWith({RunState? Function()? run}) =>
      TurnState(controller: controller, run: run == null ? this.run : run());

  @override
  List<Object?> get props => [controller, run];
}
