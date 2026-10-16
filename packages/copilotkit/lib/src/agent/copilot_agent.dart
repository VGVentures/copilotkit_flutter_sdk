part of '../client/copilot_kit_client.dart';

/// {@template copilot_agent}
/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread, and exposes
/// them through synchronous getters and the [changes] stream. Get one with
/// `CopilotKitClient.agent`.
/// {@endtemplate}
class CopilotAgent({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,
  required final CopilotKitClient _client,
  String? threadId,
}) {
  /// {@macro copilot_agent}
  ///
  /// Prefer `CopilotKitClient.agent`, which caches agents by id. A random
  /// [threadId] is generated when none is given.
  this;

  final _changes = StreamController<AgentSnapshot>.broadcast();
  final _stateChanges = StreamController<Object?>.broadcast();
  final _events = StreamController<BaseEvent>.broadcast();
  AgentSnapshot _snapshot = const AgentSnapshot();

  /// Id of the conversation thread sent with every run.
  final String threadId = threadId ?? _randomId();

  /// Current state of the agent.
  AgentSnapshot get snapshot => _snapshot;

  /// Conversation messages, oldest first.
  List<Message> get messages => _snapshot.messages;

  /// Shared agent state, or `null` if the agent sent none.
  Object? get state => _snapshot.state;

  /// Whether the agent is working: from `run()` until the whole turn ends,
  /// including frontend tool handlers and the runs that follow them.
  bool get isRunning => _snapshot.isRunning;

  /// Tool calls made by the agent, in call order.
  List<ToolCallView> get toolCalls => _snapshot.toolCalls;

  /// Emits a new [AgentSnapshot] every time the agent changes.
  Stream<AgentSnapshot> get changes => _changes.stream;

  /// Emits the shared state every time it changes.
  Stream<Object?> get stateStream => _stateChanges.stream;

  /// Emits every raw AG-UI event received from the runtime.
  Stream<BaseEvent> get events => _events.stream;

  /// Appends [message] to the conversation without starting a run.
  Future<void> addMessage(Message message) async {
    _update(_snapshot.copyWith(messages: [..._snapshot.messages, message]));
  }

  /// Runs the agent on the current messages.
  ///
  /// Same as `CopilotKitClient.runAgent(this)`. Completes when the run ends;
  /// errors go to `CopilotKitClient.onError` instead of being thrown.
  Future<void> run() => _client.runAgent(this);

  /// Stops the current run, if any.
  ///
  /// Same as `CopilotKitClient.stopAgent(this)`.
  Future<void> stop() => _client.stopAgent(this);

  /// Applies an event received from the runtime.
  void _apply(BaseEvent event) {
    _events.add(event);
    _reduce(event);
  }

  /// Applies an event produced locally (e.g. a tool result), without
  /// emitting it on [events].
  void _reduce(BaseEvent event) => _update(reduceAgentEvent(_snapshot, event));

  void _update(AgentSnapshot next) {
    if (identical(next, _snapshot)) return;
    final previous = _snapshot;
    _snapshot = next;
    _changes.add(next);
    if (!identical(next.state, previous.state)) _stateChanges.add(next.state);
  }

  Future<void> _close() async {
    await _changes.close();
    await _stateChanges.close();
    await _events.close();
  }
}
