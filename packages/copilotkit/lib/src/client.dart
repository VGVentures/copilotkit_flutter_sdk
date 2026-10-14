import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_snapshot.dart';
import 'package:copilotkit/src/agent_transport.dart';
import 'package:copilotkit/src/context.dart';
import 'package:copilotkit/src/reducer.dart';
import 'package:copilotkit/src/tools.dart';
import 'package:copilotkit/src/transport/ag_ui_transport.dart';

part 'agent.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Result sent to the agent for a tool call cut short by a stop.
const _cancelledResult = 'Tool call cancelled.';

/// Result sent to the agent for a tool call left open by a failed run.
const _failedResult = 'Tool call failed: the run ended early.';

/// Result sent to the agent for a call to a tool that isn't registered, e.g.
/// because its `CopilotTool` was unmounted. Backend tool calls never get it:
/// the runtime sends their results within the run.
const _unavailableResult = 'Tool is not available.';

/// Result sent to the agent when a handler throws. The error itself goes to
/// `onError` only, so exception details never reach the model.
const _handlerErrorResult = 'Tool failed.';

/// {@template copilot_kit_client}
/// Connects an app to a Copilot Runtime.
///
/// Owns the agents, the registered frontend tools and the context entries,
/// and attaches the tools and context to every run.
/// {@endtemplate}
class CopilotKitClient({
  /// Base URL of the runtime, e.g. `https://host/api/copilotkit`.
  required final Uri runtimeUrl,

  /// Builds the headers sent with each run, e.g. for auth.
  final HeadersBuilder? headers,

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final Map<String, Object?> properties = const {},

  /// Called with errors instead of throwing them.
  final CopilotErrorHandler? onError,
  AgentTransport? transport,
}) {
  /// {@macro copilot_kit_client}
  ///
  /// [transport] defaults to an `ag_ui`-backed transport for [runtimeUrl].
  this;

  final AgentTransport _transport =
      transport ?? AgUiTransport(runtimeUrl: runtimeUrl);
  final Map<String, CopilotAgent> _agents = {};
  final Map<String, FrontendTool> _tools = {};
  final List<_ContextEntry> _context = [];
  final Map<CopilotAgent, _Turn> _turns = {};

  /// Returns the agent with [agentId], creating it on first use.
  CopilotAgent agent(String agentId) => _agents.putIfAbsent(
    agentId,
    () => CopilotAgent(agentId: agentId, client: this),
  );

  /// Runs [agent] with all registered tools and context entries.
  ///
  /// When the agent calls registered frontend tools, their handlers run and
  /// the agent runs again with the results, until it stops calling them.
  /// Completes when that whole turn ends. Errors go to [onError] instead of
  /// being thrown. Tool calls that will never get a result (the run failed,
  /// or no registered tool handles them) are closed with a result saying so,
  /// so the next run sends a valid conversation. Does nothing if [agent] is
  /// already running.
  Future<void> runAgent(CopilotAgent agent) async {
    if (_turns.containsKey(agent)) return;
    final turn = _Turn();
    _turns[agent] = turn;
    agent._update(agent.snapshot.copyWith(isRunning: true));
    try {
      while (await _runOnce(agent, turn)) {
        final pending = _pendingToolCalls(agent);
        _closeOpenToolCalls(
          agent,
          _unavailableResult,
          where: (call) => !_tools.containsKey(call.name),
        );
        if (pending.isEmpty) return;
        for (final (call, tool) in pending) {
          final result = await _runHandler(tool, call, turn);
          if (turn.stopped) return;
          _addToolResult(agent, call, result);
        }
      }
    } finally {
      // A stop or dispose already ended the turn otherwise.
      if (identical(_turns[agent], turn)) {
        _turns.remove(agent);
        agent._update(agent.snapshot.copyWith(isRunning: false));
      }
    }
  }

  /// Streams one run of [agent]. Returns whether it finished successfully
  /// and wasn't stopped.
  Future<bool> _runOnce(CopilotAgent agent, _Turn turn) async {
    agent._update(agent.snapshot.copyWith(error: null));

    final RunAgentInput input;
    final Map<String, String> requestHeaders;
    final Stream<BaseEvent> events;
    try {
      input = RunAgentInput(
        threadId: agent.threadId,
        runId: _randomId(),
        state: agent.state,
        messages: agent.messages,
        tools: [
          for (final tool in _tools.values)
            Tool(
              name: tool.name,
              description: tool.description,
              parameters: tool.parameters.toJson(),
            ),
        ],
        context: [
          for (final entry in _context)
            Context(
              description: entry.description,
              value: jsonEncode(entry.value),
            ),
        ],
        forwardedProps: properties,
      );
      requestHeaders = await headers?.call() ?? const {};
      // Stopped or disposed while the headers were being built.
      if (turn.stopped) return false;
      events = _transport.run(
        agentId: agent.agentId,
        input: input,
        headers: requestHeaders,
      );
    } on Object catch (error, stackTrace) {
      _fail(agent, error, stackTrace);
      return false;
    }

    final run = _StreamRun(runId: input.runId, headers: requestHeaders);
    turn.run = run;
    run.subscription = events.listen(
      (event) {
        if (event is RunFinishedEvent || event is RunErrorEvent) {
          run.ended = true;
        }
        agent._apply(event);
        if (event is RunErrorEvent) onError?.call(event, StackTrace.current);
      },
      onError: (Object error, StackTrace stackTrace) {
        _fail(agent, error, stackTrace);
        run.finish();
      },
      onDone: () {
        if (!run.ended) {
          _fail(
            agent,
            StateError('The connection closed before the run finished.'),
            StackTrace.current,
          );
        }
        run.finish();
      },
      cancelOnError: true,
    );
    await run.done.future;
    turn.run = null;
    if (turn.stopped) return false;
    if (agent.snapshot.error == null) return true;
    _closeOpenToolCalls(agent, _failedResult);
    return false;
  }

  /// Executing calls to registered tools that have no result yet, with the
  /// tool that handles each.
  List<(ToolCallView, FrontendTool)> _pendingToolCalls(CopilotAgent agent) => [
    for (final call in agent.toolCalls)
      if ((call.status, _tools[call.name]) case (
        ToolCallStatus.executing,
        final tool?,
      ))
        (call, tool),
  ];

  Future<String> _runHandler(
    FrontendTool tool,
    ToolCallView call,
    _Turn turn,
  ) async {
    final signal = turn.signal = CancellationSignal();
    try {
      return await tool.handler(call.args, signal: signal);
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      return _handlerErrorResult;
    } finally {
      turn.signal = null;
    }
  }

  /// Stops the current run of [agent], closing its connection.
  ///
  /// The partial reply is kept and no further events are applied. Running
  /// tool handlers get their signal cancelled, and any tool call without a
  /// result is closed as cancelled so the conversation stays valid. If a
  /// stream was open, the runtime is also asked to stop the run; if that
  /// fails the error goes to [onError]. Does nothing if [agent] is not
  /// running.
  Future<void> stopAgent(CopilotAgent agent) async {
    final turn = _turns.remove(agent);
    if (turn == null) return;
    turn
      ..stopped = true
      ..signal?.cancel();
    final run = turn.run;
    if (run != null) await run.subscription.cancel();

    _closeOpenToolCalls(agent, _cancelledResult);
    agent._update(agent.snapshot.copyWith(isRunning: false));
    if (run == null) return;
    run.finish();
    try {
      await _transport.stop(
        agentId: agent.agentId,
        threadId: agent.threadId,
        runId: run.runId,
        headers: run.headers,
      );
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  /// Makes [tool] available to the agent on every run.
  ///
  /// A tool with the same name replaces the previous one. Returns a function
  /// that unregisters [tool]; it does nothing once [tool] was replaced.
  void Function() registerTool(FrontendTool tool) {
    _tools[tool.name] = tool;
    return () {
      if (identical(_tools[tool.name], tool)) _tools.remove(tool.name);
    };
  }

  /// Shares [value] with the agent, described by [description].
  ///
  /// [value] must be JSON-encodable; it is encoded on every run, and a run
  /// with a value that can't be encoded fails through [onError]. Use the
  /// returned entry to update or remove it.
  AgentContextEntry addContext(String description, Object? value) {
    final entry = _ContextEntry(this, description, value);
    _context.add(entry);
    return entry;
  }

  /// Stops all runs and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  Future<void> dispose() async {
    for (final turn in _turns.values) {
      turn
        ..stopped = true
        ..signal?.cancel();
      final run = turn.run;
      if (run == null) continue;
      await run.subscription.cancel();
      run.finish();
    }
    _turns.clear();
    for (final agent in _agents.values) {
      await agent._close();
    }
    await _transport.close();
  }

  /// Gives every tool call without a result (and matching [where], if set)
  /// the result [content], so the conversation stays valid for the next run.
  void _closeOpenToolCalls(
    CopilotAgent agent,
    String content, {
    bool Function(ToolCallView call)? where,
  }) {
    for (final call in agent.toolCalls) {
      if (call.status != ToolCallStatus.complete &&
          (where?.call(call) ?? true)) {
        _addToolResult(agent, call, content);
      }
    }
  }

  void _addToolResult(CopilotAgent agent, ToolCallView call, String content) {
    agent._reduce(
      ToolCallResultEvent(
        messageId: _randomId(),
        toolCallId: call.id,
        content: content,
      ),
    );
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent._update(agent.snapshot.copyWith(error: error));
    onError?.call(error, stackTrace);
  }
}

class _ContextEntry(
  final CopilotKitClient _client,
  @override final String description,
  @override var Object? value,
) implements AgentContextEntry {
  @override
  void update(Object? value) => this.value = value;

  @override
  void remove() => _client._context.remove(this);
}

/// One `runAgent` call: stream runs plus the tool handlers between them.
class _Turn {
  bool stopped = false;
  _StreamRun? run;
  CancellationSignal? signal;
}

/// One streamed request to the runtime.
class _StreamRun({
  required final String runId,
  required final Map<String, String> headers,
}) {
  // Cancelled on error (cancelOnError), on stop and on dispose.
  // ignore: cancel_subscriptions
  late StreamSubscription<BaseEvent> subscription;
  final done = Completer<void>();

  /// Whether the runtime sent `RUN_FINISHED` or `RUN_ERROR`.
  bool ended = false;

  /// Completes [done]; the stream ending and a stop or dispose can race, so
  /// only the first call has an effect.
  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

final _random = Random.secure();

String _randomId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
