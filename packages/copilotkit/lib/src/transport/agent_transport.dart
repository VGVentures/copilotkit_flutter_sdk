import 'package:ag_ui/ag_ui.dart';

/// Moves AG-UI runs between the client and a Copilot Runtime.
///
/// `CopilotKitBloc` uses an `ag_ui`-backed implementation by default.
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

  /// Asks the runtime to stop run [runId] of [agentId] on [threadId].
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  });

  /// Releases the transport's resources. It can't be used afterwards.
  Future<void> close();
}
