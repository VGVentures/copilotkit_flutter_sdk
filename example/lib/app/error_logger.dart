import 'dart:developer' as developer;

/// Logs the SDK's errors; the client calls it instead of throwing.
class const ErrorLogger() {
  /// Creates a logger.
  this;

  /// Logs [error], thrown at [stackTrace].
  void call(Object error, StackTrace stackTrace) =>
      developer.log('CopilotKit error', error: error, stackTrace: stackTrace);
}
