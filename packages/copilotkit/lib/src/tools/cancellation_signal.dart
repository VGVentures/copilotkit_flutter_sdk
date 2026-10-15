import 'dart:async';

/// Tells a tool handler that its run was stopped.
///
/// The client creates one per tool call and cancels it when the run stops.
/// Handlers check [isCancelled] or await [whenCancelled] to stop early.
class CancellationSignal() {
  /// Creates a signal that has not been cancelled yet.
  this;

  // A one-shot latch: the documented mutable exception 1 in ADR 0008.
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
