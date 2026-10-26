import 'dart:collection';
import 'dart:developer' as developer;

import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
import 'package:copilotkit/src/client/run_streamer.dart';
import 'package:copilotkit/src/client/tool_call_runner.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';
import 'package:meta/meta.dart';

/// Connects an app to a Copilot Runtime.
///
/// Owns the agents it opened, the registered client tools and the context
/// entries, and attaches the tools and context to every run.
///
/// Agents, tools and context come and go while the app runs, so this is
/// mutable: a documented exception to the immutability rule. Each agent's
/// state lives in its [CopilotAgent].
class CopilotKitClient({
  required Uri runtimeUrl,
  final HeadersBuilder? _headers,
  final Map<String, Object?>? _properties,
  final CopilotErrorHandler? _onError,
  @visibleForTesting AgentTransport? transport,
}) {
  /// Creates a client for the runtime at [runtimeUrl], e.g.
  /// `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers sent with each run, e.g. for auth.
  /// `properties` are sent with every run as its forwarded props, e.g. a
  /// model's `toJson()`.
  /// `onError` is called with errors instead of throwing them; without it
  /// they are logged. [transport] replaces the AG-UI transport to
  /// [runtimeUrl] in tests.
  this;

  final AgentTransport _transport =
      transport ?? AgUiTransport(runtimeUrl: runtimeUrl);

  final _agents = <String, CopilotAgent>{};

  final _tools = ToolRegistry();

  final _context = AgentContextStore();

  late final _runner = AgentRunner(
    transport: _transport,
    onError: _report,
    streamer: RunStreamer(
      transport: _transport,
      tools: _tools,
      context: _context,
      onError: _report,
      headers: _headers,
      properties: _properties,
    ),
    toolCalls: ToolCallRunner(tools: _tools, onError: _report),
  );

  /// The open agents, by agent id. A read-only view.
  Map<String, CopilotAgent> get agents => UnmodifiableMapView(_agents);

  /// The registered client tools, by name. A read-only view.
  Map<String, ClientTool<Object?>> get tools => _tools.tools;

  /// The context entries shared with the agent, oldest first.
  List<AgentContextEntry> get context => _context.entries;

  /// Returns the agent [agentId], opening it the first time.
  CopilotAgent agent(String agentId) =>
      _agents.putIfAbsent(agentId, () => CopilotAgent(agentId: agentId));

  /// Registers [tool]; every run sends it to the agent. Calls to a
  /// [FrontendTool] run its handler on the device, and calls to a
  /// [HumanInTheLoopTool] wait for [respondToToolCall]. Replaces a tool with
  /// the same name.
  void registerTool(ClientTool<Object?> tool) => _tools.register(tool);

  /// Unregisters [tool] if it is the tool registered under its name; a
  /// different tool registered later under the same name stays.
  ///
  /// Calls of a [HumanInTheLoopTool] that wait for the user are answered as
  /// cancelled: with the tool gone, nothing can answer them anymore. To swap
  /// a tool for an updated one, register the new tool first (it replaces the
  /// old one), then unregister the old one, which then does nothing, so no
  /// call is cancelled.
  void unregisterTool(ClientTool<Object?> tool) {
    if (_tools.unregister(tool) && tool is HumanInTheLoopTool) {
      _runner.cancelAwaiting(tool.name);
    }
  }

  /// Answers the call [toolCallId] of a [HumanInTheLoopTool] with [result],
  /// and the turn that waits for it continues with it as the tool result.
  ///
  /// A [String] [result] is sent to the agent as it is; any other value is
  /// JSON-encoded (an app model with `toJson` works), and a value that can't
  /// be encoded goes to `onError` and leaves the call waiting.
  ///
  /// Call it whenever the user decides. An answer that arrives before the
  /// client starts waiting for the call (its arguments are complete but its
  /// run has not finished streaming) is kept until it does. Does nothing when
  /// the call is unknown, belongs to no running turn, already has a result
  /// or was answered already, or when its tool is not a registered
  /// [HumanInTheLoopTool].
  void respondToToolCall(String toolCallId, Object? result) =>
      _runner.respond(toolCallId, result);

  /// Adds [entry]; every run sends it to the agent.
  void addContext(AgentContextEntry entry) => _context.add(entry);

  /// Replaces the value of the context entry [id].
  void updateContext(String id, Map<String, Object?> value) =>
      _context.update(id, value);

  /// Removes the context entry [id].
  void removeContext(String id) => _context.remove(id);

  /// Runs a turn of the agent [agentId], opening it if needed, after
  /// appending [message] if given.
  ///
  /// Completes when the turn ends and never throws: errors go to `onError`
  /// and to [CopilotAgentState.error]. Does nothing while the agent is
  /// already running, so the message is dropped too.
  Future<void> runAgent(String agentId, {Message? message}) =>
      _runner.run(agent(agentId), message: message);

  /// Stops the turn of the agent [agentId], if it is running.
  Future<void> stopAgent(String agentId) async {
    final agent = _agents[agentId];
    if (agent != null) await _runner.stop(agent);
  }

  /// Stops all runs, closes the agents and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  Future<void> close() async {
    await _runner.close();
    for (final agent in _agents.values) {
      await agent.close();
    }
    await _transport.close();
  }

  void _report(Object error, StackTrace stackTrace) {
    if (_onError case final onError?) return onError(error, stackTrace);
    developer.log(
      'CopilotKit error',
      name: 'copilotkit',
      level: 1000, // SEVERE
      error: error,
      stackTrace: stackTrace,
    );
  }
}
