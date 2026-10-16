import 'dart:async';

import 'package:copilotkit/src/tools/cancellation_signal.dart';

/// Handles a frontend tool call on the device.
///
/// Receives the tool [args], already parsed by `FrontendTool.parameters`,
/// and a [signal] that is cancelled when the run is stopped. Calls whose
/// arguments don't match the schema never reach the handler; the agent gets a
/// result listing the problems instead.
///
/// Returns the result string sent back to the agent. If it throws, the agent
/// gets a generic failure result and the error goes to
/// `CopilotKitClient.onError`.
typedef FrontendToolHandler = Future<String> Function(
  Map<String, Object?> args, {
  required CancellationSignal signal,
});
