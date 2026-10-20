import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread as its
/// [state], and adds the new state to [stream] every time it changes.
/// Open one with `CopilotKitClient.agent`.
///
/// It changes over time, so unlike the value types it is mutable: [state] is
/// replaced, never modified.
class CopilotAgent({
  required String agentId,
  String? threadId,
  final AgentEventReducer _reducer = const AgentEventReducer(),
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  /// Creates the agent [agentId].
  ///
  /// Internal: only `CopilotKitClient.agent` creates agents, so the client
  /// tracks every agent it runs. A random [threadId] is generated when none
  /// is given. The reducer applies AG-UI events to the state, and the
  /// patcher applies the app's edits to the shared state.
  @internal
  this;

  CopilotAgentState _state = CopilotAgentState(
    agentId: agentId,
    threadId: threadId ?? const Uuid().v4(),
  );

  final _states = StreamController<CopilotAgentState>.broadcast();

  /// The agent as of now. Up to date as soon as a change is made.
  CopilotAgentState get state => _state;

  /// Every new [state], from the moment of listening. Read [state] first for
  /// the current one: the stream doesn't replay it.
  Stream<CopilotAgentState> get stream => _states.stream;

  /// Whether [close] has been called. A closed agent ignores every change.
  bool get isClosed => _states.isClosed;

  /// Appends [message] to the conversation, without starting a run.
  ///
  /// Run the agent with `CopilotKitClient.runAgent`, which can also add a
  /// message.
  void addMessage(Message message) {
    _update(_state.copyWith(messages: [..._state.messages, message]));
  }

  /// Replaces every message of the conversation with [messages].
  ///
  /// Use it to reset a conversation (`setMessages([])`) or to restore a saved
  /// one. Tool calls that no message refers to anymore are dropped from
  /// `CopilotAgentState.toolCalls`. Allowed while the agent is running; the
  /// events that stream in afterwards apply on top of [messages].
  void setMessages(List<Message> messages) {
    final callIds = {
      for (final message in messages.whereType<AssistantMessage>())
        for (final call in message.toolCalls ?? const <ToolCall>[]) call.id,
    };
    _update(
      _state.copyWith(
        messages: messages,
        toolCalls: [
          for (final view in _state.toolCalls)
            if (callIds.contains(view.id)) view,
        ],
      ),
    );
  }

  /// Replaces the shared state with [state], or clears it with `null`.
  ///
  /// The next run sends [state] as `RunAgentInput.state`. A `STATE_SNAPSHOT`
  /// from the runtime replaces it again, and a `STATE_DELTA` patches it, so
  /// a local edit made during a run can be overwritten by the agent.
  void setSharedState(SharedState? state) {
    _update(_state.copyWith(sharedState: () => state));
  }

  /// Edits the shared state with the RFC 6902 JSON Patch [operations], the
  /// same format as a `STATE_DELTA`.
  ///
  /// A missing state is patched as an empty object. When an operation
  /// doesn't apply (a missing path, a failed test), none of them does: the
  /// state stays as it was and a [FormatException] is thrown.
  void patchSharedState(List<JsonPatchOperation> operations) {
    final document = _state.sharedState?.toJson() ?? const <String, Object?>{};
    final patched = _patcher.apply(document, operations);
    _update(_state.copyWith(sharedState: () => SharedState(patched)));
  }

  /// Applies an AG-UI [event], from the runtime or produced locally (a tool
  /// result).
  @internal
  void apply(BaseEvent event) => _update(_reducer.reduce(_state, event));

  /// Marks the agent running for a turn and clears the previous error.
  @internal
  void startTurn() {
    _update(_state.copyWith(isRunning: true, error: () => null));
  }

  /// Marks the turn over: it finished, failed or was stopped.
  @internal
  void endTurn() => _update(_state.copyWith(isRunning: false));

  /// Records [error], which ended the current run. A [RunErrorEvent] is
  /// recorded by [apply] instead.
  @internal
  void fail(Object error) => _update(_state.copyWith(error: () => error));

  /// Stops [stream]. Changes after this are ignored.
  Future<void> close() => _states.close();

  void _update(CopilotAgentState next) {
    if (isClosed || next == _state) return;
    _state = next;
    _states.add(next);
  }
}
