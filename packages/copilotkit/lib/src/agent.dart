// coverage:ignore-file
// Contract stub (A3); implemented in A4/A5.
import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent_snapshot.dart';
import 'package:copilotkit/src/client.dart';
import 'package:copilotkit/src/tools.dart';

/// {@template copilot_agent}
/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread, and exposes
/// them through synchronous getters and the [changes] stream. Get one with
/// `CopilotKitClient.agent`.
/// {@endtemplate}
class CopilotAgent {
  /// {@macro copilot_agent}
  ///
  /// Prefer `CopilotKitClient.agent`, which caches agents by id.
  new({required this.agentId, required this._client, this._threadId});

  final CopilotKitClient _client;
  // Read once the agent is implemented (A5).
  // ignore: unused_field
  final String? _threadId;

  /// Id of the agent on the runtime, e.g. `default`.
  final String agentId;

  /// Id of the conversation thread sent with every run.
  String get threadId => throw UnimplementedError();

  /// Current state of the agent.
  AgentSnapshot get snapshot => throw UnimplementedError();

  /// Conversation messages, oldest first.
  List<Message> get messages => snapshot.messages;

  /// Shared agent state, or `null` if the agent sent none.
  Object? get state => snapshot.state;

  /// Whether a run is in progress.
  bool get isRunning => snapshot.isRunning;

  /// Tool calls made by the agent, in call order.
  List<ToolCallView> get toolCalls => snapshot.toolCalls;

  /// Emits a new [AgentSnapshot] every time the agent changes.
  Stream<AgentSnapshot> get changes => throw UnimplementedError();

  /// Emits the shared state every time it changes.
  Stream<Object?> get stateStream => throw UnimplementedError();

  /// Emits every raw AG-UI event received from the runtime.
  Stream<BaseEvent> get events => throw UnimplementedError();

  /// Appends [message] to the conversation without starting a run.
  Future<void> addMessage(Message message) => throw UnimplementedError();

  /// Runs the agent on the current messages.
  ///
  /// Same as `CopilotKitClient.runAgent(this)`. Completes when the run ends;
  /// errors go to `CopilotKitClient.onError` instead of being thrown.
  Future<void> run() => _client.runAgent(this);

  /// Stops the current run, if any.
  ///
  /// Same as `CopilotKitClient.stopAgent(this)`.
  Future<void> stop() => _client.stopAgent(this);
}
