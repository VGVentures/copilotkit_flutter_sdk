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
import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/frontend_tool.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:copilotkit/src/tools/tool_schema.dart';
import 'package:copilotkit/src/transport/ag_ui_transport.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

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
  final Map<CopilotAgent, _Turn> _turns = {};

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
          event.agentId: CopilotAgent(agentId: event.agentId, client: this),
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
    if (agent != null) await _runAgent(agent);
  }

  Future<void> _onAgentStopRequested(
    AgentStopRequested event,
    Emitter<CopilotKitState> emit,
  ) async {
    final agent = state.agents[event.agentId];
    if (agent != null) await _stopAgent(agent);
  }

  Future<void> _runAgent(CopilotAgent agent) async {
    if (_turns.containsKey(agent)) return;
    final turn = _Turn();
    _turns[agent] = turn;
    agent.add(const AgentTurnStarted());
    try {
      while (await _runOnce(agent, turn)) {
        final pending = _pendingToolCalls(agent);
        await _closeOpenToolCalls(
          agent,
          _FallbackToolResult.unavailable,
          where: (call) => !state.tools.containsKey(call.name),
        );
        if (pending.isEmpty) return;
        for (final (call, tool) in pending) {
          final result = await _runHandler(tool, call, turn);
          if (turn.stopped) return;
          await _addToolResult(agent, call, result);
        }
      }
    } finally {
      // A stop or dispose already ended the turn otherwise.
      // This turn, not an equal one: a newer turn may have replaced it.
      if (identical(_turns[agent], turn)) {
        _turns.remove(agent);
        agent.add(const AgentTurnEnded());
        await agent.settled;
      }
    }
  }

  /// Streams one run of [agent]. Returns whether it finished successfully
  /// and wasn't stopped.
  Future<bool> _runOnce(CopilotAgent agent, _Turn turn) async {
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
        agent.add(AgentEventReceived(event));
        if (event is RunErrorEvent) _onError?.call(event, StackTrace.current);
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
    await agent.settled;
    turn.run = null;
    if (turn.stopped) return false;
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

  /// Runs the handler of [tool] for [call] and returns the result for the
  /// agent.
  ///
  /// Arguments that don't match `FrontendTool.parameters` never reach the
  /// handler: the agent gets a result listing the problems, and they are
  /// logged rather than sent to `onError`, since the agent is at fault.
  Future<String> _runHandler(
    FrontendTool tool,
    ToolCallView call,
    _Turn turn,
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
    final signal = turn.signal = CancellationSignal();
    try {
      return await tool.handler(args, signal: signal);
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      return _FallbackToolResult.handlerError.message;
    } finally {
      turn.signal = null;
    }
  }

  Future<void> _stopAgent(CopilotAgent agent) async {
    final turn = _turns.remove(agent);
    if (turn == null) return;
    turn
      ..stopped = true
      ..signal?.cancel();
    final run = turn.run;
    if (run != null) await run.subscription.cancel();

    await agent.settled;
    await _closeOpenToolCalls(agent, _FallbackToolResult.cancelled);
    agent.add(const AgentTurnEnded());
    await agent.settled;
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
      _onError?.call(error, stackTrace);
    }
  }

  /// Stops all runs, closes the agents and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  @override
  Future<void> close() async {
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
      if (call.status != ToolCallStatus.complete &&
          (where?.call(call) ?? true)) {
        await _addToolResult(agent, call, result.message);
      }
    }
  }

  Future<void> _addToolResult(
    CopilotAgent agent,
    ToolCallView call,
    String content,
  ) async {
    agent.add(
      AgentEventReceived(
        ToolCallResultEvent(
          messageId: const Uuid().v4(),
          toolCallId: call.id,
          content: content,
        ),
      ),
    );
    await agent.settled;
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent.add(AgentRunFailed(error));
    _onError?.call(error, stackTrace);
  }
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
