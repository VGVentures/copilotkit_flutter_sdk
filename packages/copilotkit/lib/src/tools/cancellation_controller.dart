import 'dart:async';

import 'package:copilotkit/src/tools/cancellation_signal.dart';

/// Owns a [CancellationSignal] and cancels it.
///
/// The client creates one per turn and hands [signal] to tool handlers, so
/// only the client can cancel a turn.
class CancellationController() {
  /// Creates a controller whose [signal] has not been cancelled yet.
  this;

  final _cancelled = Completer<void>();

  /// The read-only view for tool handlers.
  late final CancellationSignal signal = _Signal(this);

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Cancels [signal]. Calling it again has no effect.
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class const _Signal(final CancellationController _controller)
    implements CancellationSignal {
  @override
  bool get isCancelled => _controller.isCancelled;

  @override
  Future<void> get whenCancelled => _controller._cancelled.future;
}
