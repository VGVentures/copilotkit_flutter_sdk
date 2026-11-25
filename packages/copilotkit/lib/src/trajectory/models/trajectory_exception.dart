import 'package:equatable/equatable.dart';

/// A problem with capturing a trajectory, reported to the client's error
/// handler.
///
/// [code] is the code the other CopilotKit SDKs use, e.g.
/// `TRAJECTORIES_NOT_ENABLED`, `CONNECTION_LOST` or `EVENTS_DROPPED`.
class const TrajectoryException({
  /// The code of the problem, in upper snake case.
  required final String code,

  /// What went wrong.
  required final String message,

  /// The HTTP status of the runtime's answer, or `null` when there was none.
  final int? statusCode,

  /// Whether trying again could work: a dropped connection or an overloaded
  /// runtime, not a refusal.
  final bool isRetryable = false,
}) extends Equatable implements Exception {
  /// Creates the problem [code] with [message].
  this;

  @override
  List<Object?> get props => [code, message, statusCode, isRetryable];

  @override
  String toString() => 'TrajectoryException($code): $message';
}
