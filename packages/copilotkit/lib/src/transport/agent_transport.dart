/// @docImport 'package:copilotkit/src/client/client.dart';
library;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/models/runtime_info.dart';

/// Moves AG-UI runs between the client and a Copilot Runtime.
///
/// [CopilotKitClient] uses an `ag_ui`-backed implementation by default.
/// Implement or mock it to run the client without a network.
abstract interface class AgentTransport {
  /// Starts a run of [agentId] with [input] and streams its events.
  ///
  /// [headers] are sent with the request. Cancelling the subscription closes
  /// the underlying connection.
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  });

  /// Opens the thread of [input] on [agentId] and streams the events that
  /// rebuild it: the history of the thread and, when a run of it is still
  /// going, that run's events as they happen.
  ///
  /// [input] carries the thread id and an empty conversation; a replay
  /// cursor can travel in it later without changing this signature. The
  /// stream is empty when the runtime has no history for the thread.
  /// [headers] are sent with the request. Cancelling the subscription closes
  /// the underlying connection.
  Stream<BaseEvent> connect({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  });

  /// Asks the runtime to stop run [runId] of [agentId] on [threadId].
  ///
  /// Throws when the runtime rejects the request or doesn't answer in time.
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  });

  /// Asks the runtime what it is: its mode, its thread routes and its agents.
  ///
  /// [headers] are sent with the request. Throws when the runtime rejects the
  /// request, doesn't answer in time or answers with something that isn't
  /// runtime info.
  Future<RuntimeInfo> info({Map<String, String> headers = const {}});

  /// Releases the transport's resources. It can't be used afterwards.
  Future<void> close();
}
