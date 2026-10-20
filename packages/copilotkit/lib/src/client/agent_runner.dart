import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/run_input_builder.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';
import 'package:uuid/uuid.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Runs agents turn by turn.
///
/// A turn starts with a run of the agent. When the agent calls frontend
/// tools, their handlers run and the agent runs again with the results,
/// until it answers without calling one. When it calls a human-in-the-loop
/// tool, the turn waits for the user's answer (see [respond]) and continues
/// the same way, unless that tool sets `followUp` to `false`. A turn ends
/// when that happens, when a run fails, or when it is stopped.
///
/// It tracks the turn in flight for each agent and the answers to
/// human-in-the-loop calls, so it is mutable: a documented exception to the
/// immutability rule.
class AgentRunner({
  /// Sends runs and stop requests to the runtime.
  required final AgentTransport _transport,

  /// The client tools sent with every run and carried out on the device.
  required final ToolRegistry _tools,

  /// The app data sent with every run.
  required final AgentContextStore _context,

  /// Receives errors from runs, the transport and tool handlers.
  required final CopilotErrorHandler _onError,

  /// Builds the headers of each run, e.g. for auth.
  final HeadersBuilder? _headers,

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final JsonEncodable? _properties,

  /// Builds the input of each run.
  final RunInputBuilder _inputBuilder = const RunInputBuilder(),

  /// Produces the results of the client tool calls.
  final ToolCallExecutor _executor = const ToolCallExecutor(),

  /// Generates the ids of the tool results added locally.
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a runner that sends runs through the given transport.
  this;

  final _turns = <String, _Turn>{};

  final _responses = ToolResponses();

  /// Runs a turn of [agent], after appending [message] if given.
  ///
  /// Completes when the turn ends and never throws: errors go to the error
  /// handler and to `CopilotAgentState.error`. Does nothing while [agent] is
  /// already in a turn.
  Future<void> run(CopilotAgent agent, {Message? message}) async {
    final agentId = agent.state.agentId;
    if (_turns.containsKey(agentId)) return;
    final turn = _Turn(agent);
    _turns[agentId] = turn;
    // Started first, so the agent's first new state is already running.
    agent.startTurn();
    if (message != null) agent.addMessage(message);
    try {
      while (await _runOnce(agent, turn)) {
        final pending = _pendingToolCalls(agent);
        _closeOpenToolCalls(
          agent,
          FallbackToolResult.unavailable,
          where: (call) => _tools[call.name] == null,
        );
        if (pending.isEmpty) return;
        _markAwaitingResponse(agent, pending);
        var followUp = false;
        for (final (call, tool) in pending) {
          final outcome = await _executor.execute(
            tool,
            call,
            turn.signal,
            responses: _responses,
          );
          if (outcome.error case final error?) {
            _onError(error, outcome.stackTrace ?? StackTrace.current);
          }
          if (turn.signal.isCancelled) return;
          _addToolResult(agent, call, outcome.result);
          followUp |= _followsUp(tool);
        }
        if (!followUp) return;
      }
    } finally {
      // A stop or close already ended the turn otherwise, and a newer turn
      // may have replaced this one.
      if (!agent.isClosed && _turns[agentId] == turn) {
        _turns.remove(agentId);
        agent.endTurn();
      }
    }
  }

  /// Answers the human-in-the-loop call [toolCallId] with [result]: a
  /// `String` as it is, anything else JSON-encoded.
  ///
  /// An answer that arrives before the turn waits for the call (its
  /// arguments are complete but its run has not finished streaming) is kept
  /// until it does. Ignored when the call is unknown, belongs to no running
  /// turn, already has a result or was answered already, or when its tool is
  /// not a registered `HumanInTheLoopTool`. A [result] that can't be encoded
  /// goes to the error handler and leaves the call waiting.
  void respond(String toolCallId, Object? result) {
    if (!_isUnansweredHumanCall(toolCallId)) return;
    try {
      _responses.respond(toolCallId, result);
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  /// Answers the calls of the tool [toolName] that wait for the user as
  /// cancelled: with the tool gone, nobody can answer them.
  void cancelAwaiting(String toolName) {
    for (final turn in _turns.values) {
      for (final call in turn.agent.state.toolCalls) {
        if (call.name == toolName && call.awaitingResponse) {
          _responses.respond(call.id, FallbackToolResult.cancelled.message);
        }
      }
    }
  }

  /// Stops the turn of [agent]: cancels its tool handlers, closes its open
  /// tool calls and asks the runtime to stop the run in flight, if any.
  ///
  /// Does nothing when [agent] isn't in a turn. Errors from the stop request
  /// go to the error handler.
  Future<void> stop(CopilotAgent agent) async {
    final turn = _turns.remove(agent.state.agentId);
    if (turn == null) return;
    turn.signal.cancel();
    final run = turn.run;
    if (run != null) await run.subscription.cancel();

    _closeOpenToolCalls(agent, FallbackToolResult.cancelled);
    // close() ended the turn while this stop was waiting; like close(), it
    // sends no stop request.
    if (agent.isClosed) return;
    agent.endTurn();
    if (run == null) return;
    try {
      await _transport.stop(
        agentId: agent.state.agentId,
        threadId: agent.state.threadId,
        runId: run.runId,
        headers: run.headers,
      );
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  /// Cancels every turn without sending stop requests.
  Future<void> close() async {
    // A copy: a turn removes itself once its subscription is cancelled.
    for (final turn in _turns.values.toList()) {
      turn.signal.cancel();
      await turn.run?.subscription.cancel();
    }
    _responses.clear();
  }

  /// Streams one run of [agent] within [turn]. Returns whether it finished
  /// successfully and wasn't stopped.
  Future<bool> _runOnce(CopilotAgent agent, _Turn turn) async {
    final RunAgentInput input;
    final Map<String, String> headers;
    final Stream<BaseEvent> events;
    try {
      input = _inputBuilder.build(
        agent: agent.state,
        tools: _tools.tools.values,
        context: _context.entries,
        properties: _properties,
      );
      headers = await _headers?.call() ?? const {};
      // Stopped or closed while the headers were being built.
      if (turn.signal.isCancelled) return false;
      events = _transport.run(
        agentId: agent.state.agentId,
        input: input,
        headers: headers,
      );
    } on Object catch (error, stackTrace) {
      _fail(agent, error, stackTrace);
      return false;
    }

    // The stream ending and a stop can race; only the first completes it.
    final streamDone = Completer<void>();
    void finish() {
      if (!streamDone.isCompleted) streamDone.complete();
    }

    // Whether the runtime sent RUN_FINISHED or RUN_ERROR.
    var ended = false;
    turn.run = _Run(
      runId: input.runId,
      headers: headers,
      // Cancelled on error (cancelOnError), by a stop and by close().
      subscription: events.listen(
        (event) {
          if (event is RunFinishedEvent || event is RunErrorEvent) {
            ended = true;
          }
          agent.apply(event);
          if (event is RunErrorEvent) _onError(event, StackTrace.current);
        },
        onError: (Object error, StackTrace stackTrace) {
          _fail(agent, error, stackTrace);
          finish();
        },
        onDone: () {
          if (!ended) {
            _fail(
              agent,
              StateError('The connection closed before the run finished.'),
              StackTrace.current,
            );
          }
          finish();
        },
        cancelOnError: true,
      ),
    );
    await Future.any([streamDone.future, turn.signal.whenCancelled]);
    if (turn.signal.isCancelled) return false;
    turn.run = null;
    if (agent.state.error == null) return true;
    _closeOpenToolCalls(agent, FallbackToolResult.failed);
    return false;
  }

  /// Executing calls to registered tools that have no result yet, with the
  /// tool that handles each.
  List<(ToolCallView, ClientTool<Object?>)> _pendingToolCalls(
    CopilotAgent agent,
  ) => [
    for (final call in agent.state.toolCalls)
      if ((call.status, _tools[call.name]) case (
        ToolCallStatus.executing,
        final tool?,
      ))
        (call, tool),
  ];

  /// Marks the human-in-the-loop calls in [pending] as awaiting a response,
  /// all at once, so the user can answer them in any order.
  ///
  /// Calls whose arguments don't match their tool's parameters are left out:
  /// they get the invalid arguments result without waiting.
  void _markAwaitingResponse(
    CopilotAgent agent,
    List<(ToolCallView, ClientTool<Object?>)> pending,
  ) {
    for (final (call, tool) in pending) {
      if (tool is HumanInTheLoopTool && _executor.accepts(tool, call)) {
        agent.awaitResponse(call.id);
      }
    }
  }

  /// Whether the agent runs again after [tool] produced its result.
  bool _followsUp(ClientTool<Object?> tool) => switch (tool) {
    FrontendTool() => true,
    HumanInTheLoopTool(:final followUp) => followUp,
  };

  /// Whether [toolCallId] is a call of a registered `HumanInTheLoopTool`
  /// with complete arguments and no result yet, in an agent that is running
  /// a turn, and has no answer yet.
  bool _isUnansweredHumanCall(String toolCallId) =>
      !_responses.isAnswered(toolCallId) &&
      _turns.values.any(
        (turn) => turn.agent.state.toolCalls.any(
          (call) =>
              call.id == toolCallId &&
              call.status == ToolCallStatus.executing &&
              _tools[call.name] is HumanInTheLoopTool,
        ),
      );

  /// Gives every tool call without a result (and matching [where], if set)
  /// the message of [result], so the conversation stays valid for the next
  /// run.
  void _closeOpenToolCalls(
    CopilotAgent agent,
    FallbackToolResult result, {
    bool Function(ToolCallView call)? where,
  }) {
    for (final call in agent.state.toolCalls) {
      if (call.status != ToolCallStatus.complete &&
          (where?.call(call) ?? true)) {
        _addToolResult(agent, call, result.message);
      }
    }
  }

  /// A closed agent ignores the result.
  void _addToolResult(CopilotAgent agent, ToolCallView call, String content) {
    agent.apply(
      ToolCallResultEvent(
        messageId: _uuid.v4(),
        toolCallId: call.id,
        content: content,
      ),
    );
    // After the result is applied, so a late answer finds a complete call
    // and is ignored.
    _responses.remove(call.id);
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.fail(error);
    _onError(error, stackTrace);
  }
}

/// The turn in flight of one agent.
class _Turn(final CopilotAgent agent) {
  /// Cancelled when the turn is stopped or the runner is closed.
  final signal = CancellationSignal();

  /// The run being streamed, or `null` between runs.
  _Run? run;
}

/// A run being streamed: what a stop request needs, and the subscription to
/// cancel.
class const _Run({
  required final String runId,
  required final Map<String, String> headers,
  // Cancelled by the runner on stop and close, never here.
  // ignore: cancel_subscriptions
  required final StreamSubscription<BaseEvent> subscription,
});
