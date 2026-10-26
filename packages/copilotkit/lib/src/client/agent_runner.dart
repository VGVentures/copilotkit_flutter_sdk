import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/models/run_result.dart';
import 'package:copilotkit/src/client/run_streamer.dart';
import 'package:copilotkit/src/client/tool_call_runner.dart';
import 'package:copilotkit/src/client/turn.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';

/// Runs agents turn by turn.
///
/// A turn starts with a run of the agent. When the agent calls frontend
/// tools, their handlers run and the agent runs again with the results,
/// until it answers without calling one. When it calls a human-in-the-loop
/// tool, the turn waits for the user's answer (see [respond]) and continues
/// the same way, unless that tool sets `followUp` to `false`. A turn ends
/// when that happens, when a run fails, or when it is stopped.
///
/// It tracks the turn in flight for each agent, so it is mutable: a
/// documented exception to the immutability rule.
class AgentRunner({
  /// Sends stop requests to the runtime.
  required final AgentTransport _transport,

  /// Receives the errors of stop requests.
  required final CopilotErrorHandler _onError,

  /// Streams each run of a turn.
  required final RunStreamer _streamer,

  /// Produces the results of the tool calls between runs.
  required final ToolCallRunner _toolCalls,
}) {
  /// Creates a runner that streams runs with the given streamer and runs
  /// tool calls with the given tool call runner.
  this;

  final _turns = <String, Turn>{};

  /// Runs a turn of [agent], after appending [message] if given.
  ///
  /// Completes when the turn ends and never throws: errors go to the error
  /// handler and to `CopilotAgentState.error`. Does nothing while [agent] is
  /// already in a turn, or while a stop of its turn is still in flight.
  Future<void> run(CopilotAgent agent, {Message? message}) async {
    final agentId = agent.state.agentId;
    // A stop removes the turn before it ends it, so the agent is still
    // running until the stop is done.
    if (_turns.containsKey(agentId) || agent.state.isRunning) return;
    final turn = Turn(agent);
    _turns[agentId] = turn;
    // Started first, so the agent's first new state is already running.
    agent.startTurn();
    if (message != null) agent.addMessage(message);
    try {
      while (await _runOnce(turn) && await _toolCalls.runPending(turn)) {}
    } finally {
      // A stop or close already ended the turn otherwise, and a newer turn
      // may have replaced this one.
      if (!agent.isClosed && _turns[agentId] == turn) {
        _turns.remove(agentId);
        agent.endTurn();
      }
    }
  }

  /// Answers the human-in-the-loop call [toolCallId] of an agent in a turn
  /// with [result]; see `ToolCallRunner.respond`.
  void respond(String toolCallId, Object? result) =>
      _toolCalls.respond(_agentsInTurn, toolCallId, result);

  /// Answers the calls of the tool [toolName] that wait for the user as
  /// cancelled; see `ToolCallRunner.cancelAwaiting`.
  void cancelAwaiting(String toolName) =>
      _toolCalls.cancelAwaiting(_agentsInTurn, toolName);

  /// Stops the turn of [agent]: cancels its tool handlers, closes its open
  /// tool calls and asks the runtime to stop the run in flight, if any.
  ///
  /// Does nothing when [agent] isn't in a turn. Errors from cancelling the
  /// run and from the stop request go to the error handler.
  Future<void> stop(CopilotAgent agent) async {
    final turn = _turns.remove(agent.state.agentId);
    if (turn == null) return;
    turn.signal.cancel();
    final run = turn.run;
    if (run != null) {
      // A failed cancel must not skip the end of the turn below: the run
      // guard would then drop every later run of the agent.
      try {
        await run.subscription.cancel();
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }

    _toolCalls.closeOpen(agent, FallbackToolResult.cancelled);
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
    _toolCalls.clear();
  }

  Iterable<CopilotAgent> get _agentsInTurn =>
      _turns.values.map((turn) => turn.agent);

  /// Streams one run of the agent of [turn]. Returns whether it finished
  /// successfully and wasn't stopped; a failed run closes the open tool
  /// calls, so the next run sends a valid conversation.
  Future<bool> _runOnce(Turn turn) async {
    switch (await _streamer.stream(turn)) {
      case RunResult.finished:
        return true;
      case RunResult.failed:
        _toolCalls.closeOpen(turn.agent, FallbackToolResult.failed);
        return false;
      case RunResult.stopped:
        return false;
    }
  }
}
