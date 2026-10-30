import 'dart:async';

/// Tells a tool handler that its run was stopped.
///
/// The client creates one per tool call and cancels it when the run stops
/// or the client closes. Handlers check [isCancelled] or await
/// [whenCancelled] to stop early. A handler that calls [cancel] affects only
/// its own call, whose result is still what the handler returns.
class CancellationSignal() {
  /// Creates a signal that has not been cancelled yet.
  this;

  final _cancelled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the signal. Calling it again has no effect.
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
