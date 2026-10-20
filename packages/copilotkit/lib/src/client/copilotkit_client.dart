import 'dart:collection';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
import 'package:copilotkit/src/client/run_streamer.dart';
import 'package:copilotkit/src/client/tool_call_runner.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotKitErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Connects an app to a Copilot Runtime.
///
/// Owns the agents it opened, the registered client tools and the context
/// entries, and attaches the tools and context to every run.
///
/// Agents, tools and context come and go while the app runs, so this is
/// mutable: a documented exception to the immutability rule. Each agent's
/// state lives in its [CopilotKitAgent].
class CopilotKitClient({
  required Uri runtimeUrl,
  final HeadersBuilder? _headers,
  final JsonEncodable? _properties,
  final CopilotKitErrorHandler? _onError,
  AgentTransport? transport,
}) {
  /// Creates a client for the runtime at [runtimeUrl], e.g.
  /// `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers sent with each run, e.g. for auth.
  /// `properties` are sent with every run as [RunAgentInput.forwardedProps];
  /// their `toJson` must return a JSON object, or every run fails with a
  /// [FormatException].
  /// `onError` is called with errors instead of throwing them; without it
  /// they are logged. [transport] defaults to an `ag_ui`-backed transport
  /// for [runtimeUrl].
  this;

  final AgentTransport _transport =
      transport ?? AgUiTransport(runtimeUrl: runtimeUrl);

  final _agents = <String, CopilotKitAgent>{};

  final _tools = ToolRegistry();

  final _context = AgentContextStore();

  bool _isClosed = false;

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

  /// The open agents, by agent id.
  ///
  /// A read-only view.
  Map<String, CopilotKitAgent> get agents => UnmodifiableMapView(_agents);

  /// The registered client tools, by name.
  ///
  /// A read-only view.
  Map<String, ClientTool<Object?>> get tools => _tools.tools;

  /// The context entries shared with the agent, oldest first.
  List<AgentContextEntry> get context => _context.entries;

  /// Whether [close] has been called.
  ///
  /// A closed client opens no agents and runs nothing.
  bool get isClosed => _isClosed;

  /// Returns the agent [agentId], opening it the first time.
  ///
  /// Throws a [StateError] when the client is closed and the agent isn't
  /// open: it could never run.
  CopilotKitAgent agent(String agentId) => _agents.putIfAbsent(agentId, () {
    if (_isClosed) throw StateError('CopilotKitClient is closed.');
    return CopilotKitAgent(agentId: agentId);
  });

  /// Registers [tool]; every run sends it to the agent.
  ///
  /// Calls to a [FrontendTool] run its handler on the device, and calls to a
  /// [HumanInTheLoopTool] wait for [respondToToolCall]. Replaces a different
  /// tool with the same name; registering an equal one again counts as
  /// another registration (see [unregisterTool]).
  void registerTool(ClientTool<Object?> tool) => _tools.register(tool);

  /// Unregisters [tool] if it is the tool registered under its name; a
  /// different tool registered later under the same name stays. An equal
  /// tool registered several times, e.g. by two widgets, stays until each
  /// registration is undone.
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
  ///
  /// An entry with the id of one already added replaces it in place.
  void addContext(AgentContextEntry entry) => _context.add(entry);

  /// Replaces the value of the context entry [id].
  void updateContext(String id, JsonEncodable value) =>
      _context.update(id, value);

  /// Removes the context entry [id].
  void removeContext(String id) => _context.remove(id);

  /// Runs a turn of the agent [agentId], opening it if needed, after
  /// appending [message] if given.
  ///
  /// Completes when the turn ends and never throws: errors go to `onError`
  /// and to [CopilotKitAgentState.error]. Does nothing while the agent is
  /// already running, so the message is dropped too, and once the client
  /// is closed.
  Future<void> runAgent(String agentId, {Message? message}) async {
    if (_isClosed) return;
    await _runner.run(agent(agentId), message: message);
  }

  /// Stops the turn of the agent [agentId], if it is running.
  Future<void> stopAgent(String agentId) async {
    final agent = _agents[agentId];
    if (agent != null) await _runner.stop(agent);
  }

  /// Stops all runs, closes the agents and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  Future<void> close() async {
    _isClosed = true;
    await _runner.close();
    for (final agent in _agents.values) {
      await agent.close();
    }
    await _transport.close();
  }

  /// Reports [error] to `onError`, or logs it without one.
  ///
  /// Errors `onError` throws are logged too, so a broken handler can't end a
  /// turn early or make [runAgent] throw.
  void _report(Object error, StackTrace stackTrace) {
    if (_onError case final onError?) {
      try {
        return onError(error, stackTrace);
      } on Object catch (handlerError, handlerStackTrace) {
        return _log('onError threw', handlerError, handlerStackTrace);
      }
    }
    _log('CopilotKit error', error, stackTrace);
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'copilotkit',
      level: 1000, // SEVERE
      error: error,
      stackTrace: stackTrace,
    );
  }
}
