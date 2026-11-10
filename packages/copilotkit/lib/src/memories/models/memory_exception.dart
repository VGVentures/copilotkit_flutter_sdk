import 'package:copilotkit/src/memories/models/memory_error_code.dart';
import 'package:equatable/equatable.dart';

/// A request to the runtime's memory routes failed.
///
/// A runtime without memory is not a failure: see
/// `MemoryUnavailableException`.
class const MemoryException({
  /// Which kind of request failed.
  required final MemoryErrorCode code,

  /// What went wrong.
  required final String message,

  /// The HTTP status of the answer, or `null` when there was none, like on a
  /// timeout or a dropped connection.
  final int? statusCode,
}) extends Equatable implements Exception {
  /// Creates the failure [code] with [message].
  this;

  /// Whether trying again could succeed.
  ///
  /// A 4xx status is the caller's fault, so it is not retryable. Anything
  /// else, a 5xx or no answer at all, may be transient.
  bool get isRetryable {
    final status = statusCode;
    return status == null || status < 400 || status > 499;
  }

  @override
  List<Object?> get props => [code, message, statusCode];

  @override
  String toString() => 'MemoryException(${code.wireName}): $message';
}
