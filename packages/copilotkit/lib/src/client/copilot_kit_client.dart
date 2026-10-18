import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/src/agent/copilot_agent.dart';
import 'package:copilotkit/src/agent/copilot_agent_event.dart';
import 'package:copilotkit/src/client/copilot_error_handler.dart';
import 'package:copilotkit/src/client/copilot_kit_event.dart';
import 'package:copilotkit/src/client/headers_builder.dart';
import 'package:copilotkit/src/client/models/copilot_kit_state.dart';
import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:copilotkit/src/tools/cancellation_controller.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:copilotkit/src/tools/tool_schema.dart';
import 'package:copilotkit/src/transport/ag_ui_transport.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Results sent to the agent for tool calls that never ran to completion,
/// with the outcome each one gets in the call's view.
enum _FallbackToolResult {
  /// A tool call cut short by a stop.
  cancelled('Tool call cancelled.', ToolCallStatus.cancelled),

  /// A tool call left open by a failed run.
  failed('Tool call failed: the run ended early.', ToolCallStatus.failed),

  /// A call to a tool that isn't registered, e.g. because its `CopilotTool`
  /// was unmounted. Backend tool calls never get it: the runtime sends their
  /// results within the run.
  unavailable('Tool is not available.', ToolCallStatus.failed),

  /// A handler threw. The error itself goes to `onError` only, so exception
  /// details never reach the model.
  handlerError('Tool failed.', ToolCallStatus.failed);

  new(this.message, this.status);

  /// The result text sent to the agent.
  final String message;

  /// How the call ends in its view.
  final ToolCallStatus status;
}

/// {@template copilot_kit_client}
/// Connects an app to a Copilot Runtime.
///
/// Owns the agents it opened, the registered frontend tools and the context
/// entries, all in its [state], and attaches the tools and context to every
/// run. Drive it by adding a [CopilotKitEvent].
/// {@endtemplate}
class CopilotKitClient({
  /// Base URL of the runtime, e.g. `https://host/api/copilotkit`.
  required final Uri runtimeUrl,

  /// Builds the headers sent with each run, e.g. for auth.
  final HeadersBuilder? headers,

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final Map<String, Object?> properties = const {},

  /// Called with errors instead of throwing them.
  CopilotErrorHandler? onError,
  AgentTransport? transport,
}) extends Bloc<CopilotKitEvent, CopilotKitState> {
  /// {@macro copilot_kit_client}
  ///
  /// [transport] defaults to an `ag_ui`-backed transport for [runtimeUrl].
  this : super(const CopilotKitState()) {
    on<AgentOpened>(_onAgentOpened);
    on<AgentClosed>(_onAgentClosed);
    on<ToolRegistered>(_onToolRegistered);
    on<ToolUnregistered>(_onToolUnregistered);
    on<ContextAdded>(_onContextAdded);
    on<ContextUpdated>(_onContextUpdated);
    on<ContextRemoved>(_onContextRemoved);
    // A run handler lasts a whole turn; stops and other agents' runs must
    // be handled while it waits.
    on<AgentRunRequested>(_onAgentRunRequested, transformer: concurrent());
    on<AgentStopRequested>(_onAgentStopRequested, transformer: concurrent());
  }

  final AgentTransport _transport =
      transport ?? AgUiTransport(runtimeUrl: runtimeUrl);
  final CopilotErrorHandler? _onError = onError;

  /// Events added through [handled] whose handler hasn't completed.
  final List<(CopilotKitEvent, Completer<void>)> _awaited = [];

  /// Adds [event] and completes once its handler has, which for
  /// [AgentRunRequested] is the end of the whole turn.
  ///
  /// Bloc delivers events asynchronously; tests use this to read [state]
  /// or an agent's state right after an event.
  @internal
  Future<void> handled(CopilotKitEvent event) {
    final completer = Completer<void>();
    _awaited.add((event, completer));
    add(event);
    return completer.future;
  }

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

  void _onAgentOpened(AgentOpened event, Emitter<CopilotKitState> emit) {
    if (state.agents.containsKey(event.agentId)) return;
    emit(
      state.copyWith(
        agents: {
          ...state.agents,
          event.agentId: CopilotAgent(
            agentId: event.agentId,
            client: this,
            threadId: event.threadId,
          ),
        },
      ),
    );
  }

  Future<void> _onAgentClosed(
    AgentClosed event,
    Emitter<CopilotKitState> emit,
  ) async {
    final agent = state.agents[event.agentId];
    if (agent == null) return;
    // Removed first, so no new run starts on it while it stops.
    emit(
      state.copyWith(
        agents: {
          for (final MapEntry(:key, :value) in state.agents.entries)
            if (key != event.agentId) key: value,
        },
      ),
    );
    // The turn's cleanup still writes to the agent; wait for it.
    await _stopTurn(agent, emit);
    await agent.close();
  }

  void _onToolRegistered(ToolRegistered event, Emitter<CopilotKitState> emit) {
    emit(state.copyWith(tools: {...state.tools, event.tool.name: event.tool}));
  }

  void _onToolUnregistered(
    ToolUnregistered event,
    Emitter<CopilotKitState> emit,
  ) {
    // Only unregister the instance that was registered; an equal tool
    // registered later must stay.
    if (!identical(state.tools[event.tool.name], event.tool)) return;
    emit(
      state.copyWith(
        tools: {
          for (final MapEntry(:key, :value) in state.tools.entries)
            if (key != event.tool.name) key: value,
        },
      ),
    );
  }

  void _onContextAdded(ContextAdded event, Emitter<CopilotKitState> emit) {
    emit(state.copyWith(context: [...state.context, event.entry]));
  }

  void _onContextUpdated(ContextUpdated event, Emitter<CopilotKitState> emit) {
    emit(
      state.copyWith(
        context: [
          for (final entry in state.context)
            if (entry.id == event.id)
              entry.copyWith(value: event.value)
            else
              entry,
        ],
      ),
    );
  }

  void _onContextRemoved(ContextRemoved event, Emitter<CopilotKitState> emit) {
    emit(
      state.copyWith(
        context: [
          for (final entry in state.context)
            if (entry.id != event.id) entry,
        ],
      ),
    );
  }

  Future<void> _onAgentRunRequested(
    AgentRunRequested event,
    Emitter<CopilotKitState> emit,
  ) async {
    final agent = state.agents[event.agentId];
    if (agent == null || state.turns.containsKey(event.agentId)) return;
    final controller = CancellationController();
    emit(_withTurn(event.agentId, TurnState(controller: controller)));
    agent.add(const AgentTurnStarted());
    try {
      while (await _runOnce(agent, controller, emit)) {
        final pending = _pendingToolCalls(agent);
        await _closeOpenToolCalls(
          agent,
          _FallbackToolResult.unavailable,
          where: (call) => !state.tools.containsKey(call.name),
        );
        if (pending.isEmpty) return;
        for (final (call, tool) in pending) {
          final (result, status) = await _runHandler(
            tool,
            call,
            controller.signal,
          );
          if (controller.isCancelled) return;
          await _addToolResult(agent, call, result, status);
        }
      }
    } finally {
      // A stop or close already ended the turn otherwise. This turn's
      // controller, not an equal one: a newer turn may have replaced it.
      if (!agent.isClosed &&
          identical(state.turns[event.agentId]?.controller, controller)) {
        emit(_withTurn(event.agentId, null));
        agent.add(const AgentTurnEnded());
        await agent.settled;
      }
    }
  }

  Future<void> _onAgentStopRequested(
    AgentStopRequested event,
    Emitter<CopilotKitState> emit,
  ) async {
    final agent = state.agents[event.agentId];
    if (agent != null) await _stopTurn(agent, emit);
  }

  /// Stops the turn of [agent], if it has one.
  Future<void> _stopTurn(
    CopilotAgent agent,
    Emitter<CopilotKitState> emit,
  ) async {
    final turn = state.turns[agent.agentId];
    if (turn == null) return;
    emit(_withTurn(agent.agentId, null));
    turn.controller.cancel();
    final run = turn.run;
    if (run != null) await run.subscription.cancel();

    await agent.settled;
    await _closeOpenToolCalls(agent, _FallbackToolResult.cancelled);
    agent.add(const AgentTurnEnded());
    await agent.settled;
    if (run == null) return;
    try {
      await _transport.stop(
        agentId: agent.agentId,
        threadId: agent.threadId,
        runId: run.runId,
        headers: run.headers,
      );
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }

  /// The state with the turn of [agentId] replaced by [turn], or removed
  /// when [turn] is `null`.
  CopilotKitState _withTurn(String agentId, TurnState? turn) => state.copyWith(
    turns: {
      for (final MapEntry(:key, :value) in state.turns.entries)
        if (key != agentId) key: value,
      agentId: ?turn,
    },
  );

  /// Streams one run of [agent] within the turn [controller] belongs to.
  /// Returns whether it finished successfully and wasn't stopped.
  Future<bool> _runOnce(
    CopilotAgent agent,
    CancellationController controller,
    Emitter<CopilotKitState> emit,
  ) async {
    final RunAgentInput input;
    final Map<String, String> requestHeaders;
    final Stream<BaseEvent> events;
    try {
      input = RunAgentInput(
        threadId: agent.threadId,
        runId: const Uuid().v4(),
        state: agent.state.sharedState,
        messages: agent.state.messages,
        tools: [
          for (final tool in state.tools.values)
            Tool(
              name: tool.name,
              description: tool.description,
              parameters: ToolSchema(tool.parameters).toJson(),
            ),
        ],
        context: [
          for (final entry in state.context)
            Context(
              description: entry.description,
              value: jsonEncode(entry.value),
            ),
        ],
        forwardedProps: properties,
      );
      requestHeaders = await headers?.call() ?? const {};
      // Stopped or closed while the headers were being built.
      if (controller.isCancelled) return false;
      events = _transport.run(
        agentId: agent.agentId,
        input: input,
        headers: requestHeaders,
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
    // Cancelled on error (cancelOnError), by a stop and by close().
    // ignore: cancel_subscriptions
    final subscription = events.listen(
      (event) {
        if (event is RunFinishedEvent || event is RunErrorEvent) ended = true;
        agent.add(AgentEventReceived(event));
        if (event is RunErrorEvent) _onError?.call(event, StackTrace.current);
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
    );
    emit(
      _withTurn(
        agent.agentId,
        TurnState(
          controller: controller,
          run: RunState(
            runId: input.runId,
            headers: requestHeaders,
            subscription: subscription,
          ),
        ),
      ),
    );
    await Future.any([streamDone.future, controller.signal.whenCancelled]);
    await agent.settled;
    if (controller.isCancelled) return false;
    emit(_withTurn(agent.agentId, TurnState(controller: controller)));
    if (agent.state.error == null) return true;
    await _closeOpenToolCalls(agent, _FallbackToolResult.failed);
    return false;
  }

  /// Executing calls to registered tools that have no result yet, with the
  /// tool that handles each.
  List<(ToolCallView, FrontendTool)> _pendingToolCalls(CopilotAgent agent) => [
    for (final call in agent.state.toolCalls)
      if ((call.status, state.tools[call.name]) case (
        ToolCallStatus.executing,
        final tool?,
      ))
        (call, tool),
  ];

  /// Runs the handler of [tool] for [call] with the turn's [signal] and
  /// returns the result for the agent and how the call ended.
  ///
  /// Arguments that don't match `FrontendTool.parameters` never reach the
  /// handler: the agent gets a result listing the problems, and they are
  /// logged rather than sent to `onError`, since the agent is at fault.
  Future<(String, ToolCallStatus)> _runHandler(
    FrontendTool tool,
    ToolCallView call,
    CancellationSignal signal,
  ) async {
    final Map<String, Object?> args;
    switch (tool.parameters.safeParse(call.args)) {
      case Ok(:final value):
        args = value ?? const {};
      case Fail(:final error):
        final result = ToolSchema.invalidArgumentsResult(error);
        developer.log(
          'Invalid arguments for tool "${call.name}":\n$result',
          name: 'copilotkit',
          level: 900, // WARNING
          error: error,
        );
        return (result, ToolCallStatus.failed);
    }
    try {
      return (
        await tool.handler(args, signal: signal),
        ToolCallStatus.complete,
      );
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      return (
        _FallbackToolResult.handlerError.message,
        _FallbackToolResult.handlerError.status,
      );
    }
  }

  /// Stops all runs, closes the agents and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  @override
  Future<void> close() async {
    for (final turn in state.turns.values) {
      turn.controller.cancel();
      await turn.run?.subscription.cancel();
    }
    for (final agent in state.agents.values) {
      await agent.close();
    }
    await _transport.close();
    await super.close();
  }

  /// Gives every tool call without a result (and matching [where], if set)
  /// the message of [result], so the conversation stays valid for the next run.
  Future<void> _closeOpenToolCalls(
    CopilotAgent agent,
    _FallbackToolResult result, {
    bool Function(ToolCallView call)? where,
  }) async {
    for (final call in agent.state.toolCalls) {
      if (!call.status.isFinished && (where?.call(call) ?? true)) {
        await _addToolResult(agent, call, result.message, result.status);
      }
    }
  }

  Future<void> _addToolResult(
    CopilotAgent agent,
    ToolCallView call,
    String content,
    ToolCallStatus status,
  ) async {
    agent.add(
      AgentToolCallClosed(
        toolCallId: call.id,
        messageId: const Uuid().v4(),
        content: content,
        status: status,
      ),
    );
    await agent.settled;
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.add(AgentRunFailed(error));
    _onError?.call(error, stackTrace);
  }
}
