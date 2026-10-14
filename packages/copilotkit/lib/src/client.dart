// coverage:ignore-file
// Contract stub (A3); implemented in A5 (runs), A7 (tools) and A8 (context).
import 'package:copilotkit/src/agent.dart';
import 'package:copilotkit/src/agent_transport.dart';
import 'package:copilotkit/src/context.dart';
import 'package:copilotkit/src/tools.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// {@template copilot_kit_client}
/// Connects an app to a Copilot Runtime.
///
/// Owns the agents, the registered frontend tools and the context entries,
/// and attaches the tools and context to every run.
/// {@endtemplate}
class CopilotKitClient {
  /// {@macro copilot_kit_client}
  new({
    required this.runtimeUrl,
    this.headers,
    this.properties = const {},
    this.onError,
    this._transport,
  });

  // Read once runs are implemented (A5).
  // ignore: unused_field
  final AgentTransport? _transport;

  /// Base URL of the runtime, e.g. `https://host/api/copilotkit`.
  final Uri runtimeUrl;

  /// Builds the headers sent with each run, e.g. for auth.
  final HeadersBuilder? headers;

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final Map<String, Object?> properties;

  /// Called with errors instead of throwing them.
  final CopilotErrorHandler? onError;

  /// Returns the agent with [agentId], creating it on first use.
  CopilotAgent agent(String agentId) => throw UnimplementedError();

  /// Runs [agent] with all registered tools and context entries.
  ///
  /// Completes when the run ends, including any follow-up runs triggered by
  /// frontend tools. Errors go to [onError] instead of being thrown.
  Future<void> runAgent(CopilotAgent agent) => throw UnimplementedError();

  /// Stops the current run of [agent], closing its connection.
  Future<void> stopAgent(CopilotAgent agent) => throw UnimplementedError();

  /// Makes [tool] available to the agent on every run.
  ///
  /// Returns a function that unregisters the tool.
  void Function() registerTool(FrontendTool tool) => throw UnimplementedError();

  /// Shares [value] with the agent, described by [description].
  ///
  /// Use the returned entry to update or remove it.
  AgentContextEntry addContext(String description, Object? value) =>
      throw UnimplementedError();

  /// Stops all runs and releases the transport.
  Future<void> dispose() => throw UnimplementedError();
}
