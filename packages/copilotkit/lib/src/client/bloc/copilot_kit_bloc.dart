import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ack/ack.dart';
import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/src/agent/bloc/copilot_agent_bloc.dart';
import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:copilotkit/src/context/agent_context_entry.dart';
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:copilotkit/src/tools/tool_schema.dart';
import 'package:copilotkit/src/transport/ag_ui_transport.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_kit_event.dart';
part 'copilot_kit_state.dart';

/// Returns the headers sent with a run; called once per run.
typedef HeadersBuilder = Future<Map<String, String>> Function();

/// Receives errors from runs, transports and tool handlers.
typedef CopilotErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Results sent to the agent for tool calls that never ran to completion.
enum _FallbackToolResult {
  /// A tool call cut short by a stop.
  cancelled('Tool call cancelled.'),

  /// A tool call left open by a failed run.
  failed('Tool call failed: the run ended early.'),

  /// A call to a tool that isn't registered, e.g. because its `CopilotTool`
  /// was unmounted. Backend tool calls never get it: the runtime sends their
  /// results within the run.
  unavailable('Tool is not available.'),

  /// A handler threw. The error itself goes to `onError` only, so exception
  /// details never reach the model.
  handlerError('Tool failed.');

  new(this.message);

  /// The result text sent to the agent.
  final String message;
}

/// Connects an app to a Copilot Runtime.
///
/// Owns the agents it opened, the registered frontend tools and the context
/// entries, all in its [state], and attaches the tools and context to every
/// run. Drive it by adding a [CopilotKitEvent].
class CopilotKitBloc({
  required Uri runtimeUrl,
  final HeadersBuilder? _headers,
  final Map<String, Object?> _properties = const {},
  CopilotErrorHandler? onError,
  AgentTransport? transport,
}) extends Bloc<CopilotKitEvent, CopilotKitState> {
  /// Creates a client for the runtime at [runtimeUrl], e.g.
  /// `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers sent with each run, e.g. for auth.
  /// `properties` are sent with every run as `RunAgentInput.forwardedProps`.
  /// [onError] is called with errors instead of throwing them, after
  /// `BlocObserver.onError`. [transport] defaults to an `ag_ui`-backed
  /// transport for [runtimeUrl].
  this : super(const CopilotKitState()) {
    on<AgentOpened>(_onAgentOpened);
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

  /// Reports [error] to the `onError` callback, after `BlocObserver.onError`.
  ///
  /// The client reports its errors with [addError] instead of throwing them,
  /// so observers and the callback see the same errors.
  @override
  void onError(Object error, StackTrace stackTrace) {
    super.onError(error, stackTrace);
    _onError?.call(error, stackTrace);
  }

  void _onAgentOpened(AgentOpened event, Emitter<CopilotKitState> emit) {
    if (state.agents.containsKey(event.agentId)) return;
    emit(
      state.copyWith(
        agents: {
          ...state.agents,
          event.agentId: CopilotAgentBloc(agentId: event.agentId),
        },
      ),
    );
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
    final signal = CancellationSignal();
    emit(_withTurn(event.agentId, TurnState(signal: signal)));
    // Started first, so the agent's first new state is already running.
    agent.add(const AgentTurnStarted());
    if (event.message case final message?) {
      agent.add(AgentMessageAdded(message));
    }
    try {
      // Messages the app added before this run go into its input.
      await _settle(agent);
      while (await _runOnce(agent, signal, emit)) {
        final pending = _pendingToolCalls(agent);
        await _closeOpenToolCalls(
          agent,
          _FallbackToolResult.unavailable,
          where: (call) => !state.tools.containsKey(call.name),
        );
        if (pending.isEmpty) return;
        for (final (call, tool) in pending) {
          final result = await _runHandler(tool, call, signal);
          if (signal.isCancelled) return;
          await _addToolResult(agent, call, result);
        }
      }
    } finally {
      // A stop or close already ended the turn otherwise. This turn's
      // signal, not an equal one: a newer turn may have replaced it.
      if (!agent.isClosed &&
          identical(state.turns[event.agentId]?.signal, signal)) {
        emit(_withTurn(event.agentId, null));
        agent.add(const AgentTurnEnded());
        await _settle(agent);
      }
    }
  }

  Future<void> _onAgentStopRequested(
    AgentStopRequested event,
    Emitter<CopilotKitState> emit,
  ) async {
    final agent = state.agents[event.agentId];
    final turn = state.turns[event.agentId];
    if (agent == null || turn == null) return;
    emit(_withTurn(event.agentId, null));
    turn.signal.cancel();
    final run = turn.run;
    if (run != null) await run.subscription.cancel();

    await _settle(agent);
    await _closeOpenToolCalls(agent, _FallbackToolResult.cancelled);
    // close() ended the turn while this stop was waiting; like close(), it
    // sends no stop request.
    if (agent.isClosed) return;
    agent.add(const AgentTurnEnded());
    await _settle(agent);
    if (run == null) return;
    try {
      await _transport.stop(
        agentId: agent.state.agentId,
        threadId: agent.state.threadId,
        runId: run.runId,
        headers: run.headers,
      );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
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

  /// The input for a new run of [agent], with the registered tools and
  /// context.
  RunAgentInput _buildInput(CopilotAgentBloc agent) => RunAgentInput(
    threadId: agent.state.threadId,
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
        Context(description: entry.description, value: jsonEncode(entry.value)),
    ],
    forwardedProps: _properties,
  );

  /// Streams one run of [agent] within the turn [signal] belongs to.
  /// Returns whether it finished successfully and wasn't stopped.
  Future<bool> _runOnce(
    CopilotAgentBloc agent,
    CancellationSignal signal,
    Emitter<CopilotKitState> emit,
  ) async {
    final RunAgentInput input;
    final Map<String, String> requestHeaders;
    final Stream<BaseEvent> events;
    try {
      input = _buildInput(agent);
      requestHeaders = await _headers?.call() ?? const {};
      // Stopped or closed while the headers were being built.
      if (signal.isCancelled) return false;
      events = _transport.run(
        agentId: agent.state.agentId,
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
        if (event is RunErrorEvent) addError(event, StackTrace.current);
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
        agent.state.agentId,
        TurnState(
          signal: signal,
          run: RunState(
            runId: input.runId,
            headers: requestHeaders,
            subscription: subscription,
          ),
        ),
      ),
    );
    await Future.any([streamDone.future, signal.whenCancelled]);
    await _settle(agent);
    if (signal.isCancelled) return false;
    emit(_withTurn(agent.state.agentId, TurnState(signal: signal)));
    if (agent.state.error == null) return true;
    await _closeOpenToolCalls(agent, _FallbackToolResult.failed);
    return false;
  }

  /// Executing calls to registered tools that have no result yet, with the
  /// tool that handles each.
  List<(ToolCallView, FrontendTool)> _pendingToolCalls(
    CopilotAgentBloc agent,
  ) => [
    for (final call in agent.state.toolCalls)
      if ((call.status, state.tools[call.name]) case (
        ToolCallStatus.executing,
        final tool?,
      ))
        (call, tool),
  ];

  /// Runs the handler of [tool] for [call] with the turn's [signal] and
  /// returns the result for the agent.
  ///
  /// Arguments that don't match `FrontendTool.parameters` never reach the
  /// handler: the agent gets a result listing the problems, and they are
  /// logged rather than sent to `onError`, since the agent is at fault.
  Future<String> _runHandler(
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
        return result;
    }
    try {
      return await tool.handler(args, signal: signal);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      return _FallbackToolResult.handlerError.message;
    }
  }

  /// Stops all runs, closes the agents and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  @override
  Future<void> close() async {
    for (final turn in state.turns.values) {
      turn.signal.cancel();
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
    CopilotAgentBloc agent,
    _FallbackToolResult result, {
    bool Function(ToolCallView call)? where,
  }) async {
    for (final call in agent.state.toolCalls) {
      if (call.status != ToolCallStatus.complete &&
          (where?.call(call) ?? true)) {
        await _addToolResult(agent, call, result.message);
      }
    }
  }

  Future<void> _addToolResult(
    CopilotAgentBloc agent,
    ToolCallView call,
    String content,
  ) async {
    if (agent.isClosed) return;
    agent.add(
      AgentEventReceived(
        ToolCallResultEvent(
          messageId: const Uuid().v4(),
          toolCallId: call.id,
          content: content,
        ),
      ),
    );
    await _settle(agent);
  }

  /// Completes once every event added to [agent] so far has been applied.
  static Future<void> _settle(CopilotAgentBloc agent) {
    if (agent.isClosed) return Future.value();
    final completer = Completer<void>();
    agent.add(AgentSettleRequested(completer));
    return completer.future;
  }

  void _fail(CopilotAgentBloc agent, Object error, StackTrace stackTrace) {
    agent.add(AgentRunFailed(error));
    addError(error, stackTrace);
  }
}
