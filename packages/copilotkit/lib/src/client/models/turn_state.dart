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
}) extends Equatable {
  /// Creates the state of a turn.
  this;

  @override
  List<Object?> get props => [signal, run];
}
