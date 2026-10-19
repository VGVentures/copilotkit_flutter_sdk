import 'dart:async';

import 'package:copilotkit/copilotkit.dart';

/// A [CopilotKitBloc] whose events can be awaited.
///
/// Bloc delivers events asynchronously; each method adds an event and waits
/// for its handler, so the next line can read the client's or an agent's
/// state.
class TestCopilotKitBloc({
  required super.runtimeUrl,
  super.headers,
  super.properties,
  super.onError,
  super.transport,
}) extends CopilotKitBloc {
  /// Creates a client for the runtime at `runtimeUrl`.
  this;

  /// Events added through [handled] whose handler hasn't completed.
  final List<(CopilotKitEvent, Completer<void>)> _awaited = [];

  /// Adds [event] and completes once its handler has, which for
  /// [AgentRunRequested] is the end of the whole turn.
  Future<void> handled(CopilotKitEvent event) {
    final completer = Completer<void>();
    _awaited.add((event, completer));
    add(event);
    return completer.future;
  }

  /// Opens and returns the agent [agentId].
  Future<CopilotAgentBloc> openAgent(String agentId) async {
    await handled(AgentOpened(agentId));
    return state.agents[agentId]!;
  }

  /// Runs [agent] and returns once the whole turn has ended.
  Future<void> runAgent(CopilotAgentBloc agent, {Message? message}) =>
      handled(AgentRunRequested(agent.state.agentId, message: message));

  /// Stops [agent] and returns once the stop has been handled.
  Future<void> stopAgent(CopilotAgentBloc agent) =>
      handled(AgentStopRequested(agent.state.agentId));

  /// Registers [tool].
  Future<void> registerTool(FrontendTool tool) => handled(ToolRegistered(tool));

  /// Unregisters [tool].
  Future<void> unregisterTool(FrontendTool tool) =>
      handled(ToolUnregistered(tool));

  /// Adds [entry] to the context.
  Future<void> addContext(AgentContextEntry entry) =>
      handled(ContextAdded(entry));

  @override
  void onDone(CopilotKitEvent event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    // The instance that was added, not an equal event added elsewhere.
    _awaited.removeWhere((entry) {
      if (!identical(entry.$1, event)) return false;
      entry.$2.complete();
      return true;
    });
  }
}
