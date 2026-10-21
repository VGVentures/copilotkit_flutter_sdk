import 'package:equatable/equatable.dart';

/// An error the runtime reported for a run, e.g. a rejected API key.
///
/// Set as `CopilotAgentState.error` and passed to the `onError` of
/// `CopilotKitClient` when the run fails this way.
class const RunError({
  /// What went wrong, as the runtime describes it.
  required final String message,

  /// A code for the error, if the runtime sends one.
  final String? code,
}) extends Equatable implements Exception {
  /// Creates an error the runtime reported.
  this;

  @override
  List<Object?> get props => [message, code];

  @override
  String toString() =>
      code == null ? 'RunError: $message' : 'RunError($code): $message';
}
