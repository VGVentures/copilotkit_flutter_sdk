import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:equatable/equatable.dart';

/// One `AgentRunRequested` turn: the stream runs plus the tool handlers
/// between them, until the agent stops calling tools or the turn is stopped.
class const TurnState({
  /// Cancelled when the turn is stopped or the client closes. Tool handlers
  /// receive it; `isCancelled` is the turn's "stopped" flag.
  required final CancellationSignal signal,

  /// The run whose stream is open, or `null` between runs.
  final RunState? run,

  /// Completes once a stop has finished cleaning up, or `null` while the turn
  /// isn't being stopped. The turn stays in the state until then.
  final Future<void>? stopped,
}) extends Equatable {
  /// Creates the state of a turn.
  this;

  /// Returns a copy with [run] or [stopped] replaced; `run: () => null`
  /// clears the run.
  TurnState copyWith({RunState? Function()? run, Future<void>? stopped}) =>
      TurnState(
        signal: signal,
        run: run == null ? this.run : run(),
        stopped: stopped ?? this.stopped,
      );

  @override
  List<Object?> get props => [signal, run, stopped];
}
