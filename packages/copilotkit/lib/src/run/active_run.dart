import 'dart:async';

import 'package:ag_ui/ag_ui.dart';

/// A run being streamed: what a stop request needs, and the subscription to
/// cancel.
class const ActiveRun({
  /// The id of the run, sent with a stop request.
  required final String runId,

  /// The headers the run was sent with, sent again with a stop request.
  required final Map<String, String> headers,

  // Cancelled by the runner on stop and close.
  // ignore: cancel_subscriptions
  /// The run's events. Cancelled by a stop or a close, never by the
  /// streamer.
  required final StreamSubscription<BaseEvent> subscription,
}) {
  /// Creates the handle of a run being streamed.
  this;
}
