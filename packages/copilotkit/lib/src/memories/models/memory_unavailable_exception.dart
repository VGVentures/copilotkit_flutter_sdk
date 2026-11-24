import 'package:equatable/equatable.dart';

/// The runtime has no memory to offer this app.
///
/// The runtime answered 404 (the routes aren't mounted, because it has no
/// `memory.access`), 403 (the app is denied), 422 (it has no Intelligence
/// project) or 501. It is not a failure: show that memory isn't available
/// instead of an error.
class const MemoryUnavailableException(
  /// The HTTP status of the answer.
  final int statusCode,
) extends Equatable implements Exception {
  /// Creates the exception for an answer with [statusCode].
  this;

  @override
  List<Object?> get props => [statusCode];

  @override
  String toString() => 'MemoryUnavailableException($statusCode)';
}
