import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/agent_runner.dart';
import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:copilotkit/src/client/run_input_builder.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:copilotkit/src/transport/transport.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_kit_event.dart';
part 'copilot_kit_state.dart';

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
  final RunInputBuilder _inputBuilder = const RunInputBuilder(),
  final ToolCallExecutor _executor = const ToolCallExecutor(),
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
          event.agentId: CopilotAgent(agentId: event.agentId),
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
    agent.startTurn();
    if (event.message case final message?) agent.addMessage(message);
    try {
      while (await _runOnce(agent, signal, emit)) {
        final pending = _pendingToolCalls(agent);
        _closeOpenToolCalls(
          agent,
          FallbackToolResult.unavailable,
          where: (call) => !state.tools.containsKey(call.name),
        );
        if (pending.isEmpty) return;
        for (final (call, tool) in pending) {
          final result = await _runHandler(tool, call, signal);
          if (signal.isCancelled) return;
          _addToolResult(agent, call, result);
        }
      }
    } finally {
      // A stop or close already ended the turn otherwise. This turn's
      // signal, not an equal one: a newer turn may have replaced it.
      if (!agent.isClosed &&
          identical(state.turns[event.agentId]?.signal, signal)) {
        emit(_withTurn(event.agentId, null));
        agent.endTurn();
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
  RunAgentInput _buildInput(CopilotAgent agent) => _inputBuilder.build(
    agent: agent.state,
    tools: state.tools.values,
    context: state.context,
    properties: _properties,
  );

  /// Streams one run of [agent] within the turn [signal] belongs to.
  /// Returns whether it finished successfully and wasn't stopped.
  Future<bool> _runOnce(
    CopilotAgent agent,
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
        agent.apply(event);
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
    if (signal.isCancelled) return false;
    emit(_withTurn(agent.state.agentId, TurnState(signal: signal)));
    if (agent.state.error == null) return true;
    _closeOpenToolCalls(agent, FallbackToolResult.failed);
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

  /// Runs the handler of [tool] for [call] with the turn's [signal],
  /// reports a handler error, and returns the result for the agent.
  Future<String> _runHandler(
    FrontendTool tool,
    ToolCallView call,
    CancellationSignal signal,
  ) async {
    final outcome = await _executor.execute(tool, call, signal);
    if (outcome.error case final error?) {
      addError(error, outcome.stackTrace ?? StackTrace.current);
    }
    return outcome.result;
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
        messageId: const Uuid().v4(),
        toolCallId: call.id,
        content: content,
      ),
    );
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.fail(error);
    addError(error, stackTrace);
  }
}
