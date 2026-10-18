import 'dart:async';

/// Tells a tool handler that its run was stopped.
///
/// Handlers check [isCancelled] or await [whenCancelled] to stop early. They
/// can't cancel it: only the owner's `CancellationController` can.
abstract interface class CancellationSignal {
  /// A signal that is never cancelled, e.g. to call a handler in a test.
  const factory none() = _NeverCancelled;

  /// Whether the run was stopped.
  bool get isCancelled;

  /// Completes when the run is stopped.
  Future<void> get whenCancelled;
}

class const _NeverCancelled() implements CancellationSignal {
  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;
}
