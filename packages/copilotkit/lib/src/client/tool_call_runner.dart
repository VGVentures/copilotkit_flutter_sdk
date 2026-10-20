import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/run_streamer.dart';
import 'package:copilotkit/src/client/turn.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:uuid/uuid.dart';

/// Produces the results of the client tool calls of a turn and adds them to
/// the agent.
///
/// A [FrontendTool] call runs its handler; a [HumanInTheLoopTool] call waits
/// for the user's answer (see [respond]). It keeps those answers, so it is
/// mutable: a documented exception to the immutability rule (ADR 0009).
class ToolCallRunner({
  /// The client tools that handle the calls.
  required final ToolRegistry _tools,

  /// Receives the errors of tool handlers and answers that can't be encoded.
  required final CopilotErrorHandler _onError,

  /// Produces the result of each call.
  final ToolCallExecutor _executor = const ToolCallExecutor(),

  /// Generates the ids of the tool results added locally.
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a runner for the calls of the tools in the registry.
  this;

  final _responses = ToolResponses();

  /// Produces the results of the executing calls of the agent of [turn] to
  /// registered tools, in call order, and returns whether the agent should
  /// run again with them.
  ///
  /// Calls to tools that aren't registered get the unavailable result. The
  /// human-in-the-loop calls are all marked as awaiting a response first, so
  /// the user can answer them in any order. Returns `false` when there was
  /// nothing to run, when [turn] was stopped meanwhile, or when every call
  /// was to a human-in-the-loop tool with `followUp` set to `false`.
  Future<bool> runPending(Turn turn) async {
    final agent = turn.agent;
    final pending = _pendingToolCalls(agent);
    closeOpen(
      agent,
      FallbackToolResult.unavailable,
      where: (call) => _tools[call.name] == null,
    );
    if (pending.isEmpty) return false;
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
      if (turn.signal.isCancelled) return false;
      _addToolResult(agent, call, outcome.result);
      followUp |= _followsUp(tool);
    }
    return followUp;
  }

  /// Answers the human-in-the-loop call [toolCallId] of one of [agents] with
  /// [result]: a `String` as it is, anything else JSON-encoded.
  ///
  /// [agents] are the agents in a turn. An answer that arrives before
  /// [runPending] waits for the call (its arguments are complete but its run
  /// has not finished streaming) is kept until it does. Ignored when the
  /// call is unknown, already has a result or was answered already, or when
  /// its tool is not a registered `HumanInTheLoopTool`. A [result] that
  /// can't be encoded goes to the error handler and leaves the call waiting.
  void respond(
    Iterable<CopilotAgent> agents,
    String toolCallId,
    Object? result,
  ) {
    if (!_isUnansweredHumanCall(agents, toolCallId)) return;
    try {
      _responses.respond(toolCallId, result);
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  /// Answers the calls of the tool [toolName] in [agents] that wait for the
  /// user as cancelled: with the tool gone, nobody can answer them.
  void cancelAwaiting(Iterable<CopilotAgent> agents, String toolName) {
    for (final agent in agents) {
      for (final call in agent.state.toolCalls) {
        if (call.name == toolName && call.awaitingResponse) {
          _responses.respond(call.id, FallbackToolResult.cancelled.message);
        }
      }
    }
  }

  /// Gives every tool call of [agent] without a result (and matching
  /// [where], if set) the message of [result], so the conversation stays
  /// valid for the next run.
  void closeOpen(
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

  /// Forgets every answer.
  void clear() => _responses.clear();

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

  /// Marks the human-in-the-loop calls in [pending] as awaiting a response.
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
  /// in one of [agents] with complete arguments, no result and no answer
  /// yet.
  bool _isUnansweredHumanCall(
    Iterable<CopilotAgent> agents,
    String toolCallId,
  ) =>
      !_responses.isAnswered(toolCallId) &&
      agents.any(
        (agent) => agent.state.toolCalls.any(
          (call) =>
              call.id == toolCallId &&
              call.status == ToolCallStatus.executing &&
              _tools[call.name] is HumanInTheLoopTool,
        ),
      );

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
}
