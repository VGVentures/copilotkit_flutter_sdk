// The subscription is a handle held by the state and cancelled by the client
// on stop and close, never here (ADR 0008).
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:equatable/equatable.dart';

/// One streamed request to the runtime, open until it ends or is stopped.
class const RunState({
  /// Id of the run, sent to the runtime's stop route.
  required final String runId,

  /// Headers the run was started with; the stop request reuses them.
  required final Map<String, String> headers,

  /// The open event stream. A handle, not a value: compared by identity and
  /// only ever cancelled, by the client on stop and close (ADR 0008).
  required final StreamSubscription<BaseEvent> subscription,
}) extends Equatable {
  /// Creates the state of an open run.
  this;

  @override
  List<Object?> get props => [runId, headers, subscription];
}
