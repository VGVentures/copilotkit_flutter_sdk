import 'package:equatable/equatable.dart';

/// The runtime refused a request because the thread already has a run going.
///
/// An Intelligence runtime answers `409` when a thread is busy. Wait for the
/// run to end, or stop it, and try again.
class const ThreadLockedException({
  /// What the runtime said, if anything.
  final String? message,
}) extends Equatable implements Exception {
  /// Creates an exception for a locked thread.
  this;

  @override
  List<Object?> get props => [message];

  @override
  String toString() => message == null
      ? 'ThreadLockedException: the thread already has a run going.'
      : 'ThreadLockedException: $message';
}
