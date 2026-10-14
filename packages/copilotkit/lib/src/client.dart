import 'dart:async';
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

/// {@template copilot_kit_client}
/// Connects an app to a Copilot Runtime.
///
/// Owns the agents, the registered frontend tools and the context entries,
/// and attaches the tools and context to every run.
/// {@endtemplate}
class CopilotKitClient {
  /// {@macro copilot_kit_client}
  ///
  /// [transport] defaults to an `ag_ui`-backed transport for [runtimeUrl].
  new({
    required this.runtimeUrl,
    this.headers,
    this.properties = const {},
    this.onError,
    AgentTransport? transport,
  }) : _transport = transport ?? AgUiTransport(runtimeUrl: runtimeUrl);

  final AgentTransport _transport;
  final Map<String, CopilotAgent> _agents = {};
  final Map<CopilotAgent, _ActiveRun> _activeRuns = {};

  /// Base URL of the runtime, e.g. `https://host/api/copilotkit`.
  final Uri runtimeUrl;

  /// Builds the headers sent with each run, e.g. for auth.
  final HeadersBuilder? headers;

  /// Sent with every run as `RunAgentInput.forwardedProps`.
  final Map<String, Object?> properties;

  /// Called with errors instead of throwing them.
  final CopilotErrorHandler? onError;

  /// Returns the agent with [agentId], creating it on first use.
  CopilotAgent agent(String agentId) => _agents.putIfAbsent(
    agentId,
    () => CopilotAgent(agentId: agentId, client: this),
  );

  /// Runs [agent] with all registered tools and context entries.
  ///
  /// Completes when the run ends, including any follow-up runs triggered by
  /// frontend tools. Errors go to [onError] instead of being thrown. Does
  /// nothing if [agent] is already running.
  Future<void> runAgent(CopilotAgent agent) async {
    if (agent.isRunning) return;
    agent._update(agent.snapshot.copyWith(isRunning: true, error: null));

    final Map<String, String> requestHeaders;
    try {
      requestHeaders = await headers?.call() ?? const {};
    } on Object catch (error, stackTrace) {
      _fail(agent, error, stackTrace);
      return;
    }

    final input = RunAgentInput(
      threadId: agent.threadId,
      runId: _randomId(),
      state: agent.state,
      messages: agent.messages,
      tools: const [],
      context: const [],
      forwardedProps: properties,
    );
    final run = _ActiveRun();
    _activeRuns[agent] = run;
    run.subscription = _transport
        .run(agentId: agent.agentId, input: input, headers: requestHeaders)
        .listen(
          agent._apply,
          onError: (Object error, StackTrace stackTrace) {
            _fail(agent, error, stackTrace);
            run.done.complete();
          },
          onDone: () {
            if (agent.isRunning) {
              _fail(
                agent,
                StateError('The connection closed before the run finished.'),
                StackTrace.current,
              );
            }
            run.done.complete();
          },
          cancelOnError: true,
        );
    await run.done.future;
    _activeRuns.remove(agent);
  }

  /// Stops the current run of [agent], closing its connection.
  // coverage:ignore-start
  Future<void> stopAgent(CopilotAgent agent) => throw UnimplementedError();

  /// Makes [tool] available to the agent on every run.
  ///
  /// Returns a function that unregisters the tool.
  void Function() registerTool(FrontendTool tool) => throw UnimplementedError();

  /// Shares [value] with the agent, described by [description].
  ///
  /// Use the returned entry to update or remove it.
  AgentContextEntry addContext(String description, Object? value) =>
      throw UnimplementedError();
  // coverage:ignore-end

  /// Stops all runs and releases the transport.
  ///
  /// The client and its agents can't be used afterwards.
  Future<void> dispose() async {
    for (final run in _activeRuns.values) {
      await run.subscription.cancel();
      if (!run.done.isCompleted) run.done.complete();
    }
    _activeRuns.clear();
    for (final agent in _agents.values) {
      await agent._close();
    }
    await _transport.close();
  }

  void _fail(CopilotAgent agent, Object error, StackTrace stackTrace) {
    agent._update(agent.snapshot.copyWith(isRunning: false, error: error));
    onError?.call(error, stackTrace);
  }
}

class _ActiveRun {
  // Cancelled on error (cancelOnError), on dispose and by stopAgent.
  // ignore: cancel_subscriptions
  late StreamSubscription<BaseEvent> subscription;
  final done = Completer<void>();
}

final _random = Random.secure();

String _randomId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
