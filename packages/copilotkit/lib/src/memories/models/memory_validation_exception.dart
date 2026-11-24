import 'package:equatable/equatable.dart';

/// A value the app passed breaks a limit of the runtime's memory routes.
///
/// It is thrown before anything is sent, because the runtime rejects the
/// request.
class const MemoryValidationException(
  /// Which limit the value breaks.
  final String message,
) extends Equatable implements Exception {
  /// Creates the exception for the broken limit [message].
  this;

  @override
  List<Object?> get props => [message];

  @override
  String toString() => 'MemoryValidationException: $message';
}
