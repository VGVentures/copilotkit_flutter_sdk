import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/run_error.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:json_utils/json_utils.dart';

/// Applies AG-UI events to a [CopilotAgentState].
class const AgentEventMapper({
  /// Parses the streamed arguments of tool calls.
  final PartialJsonParser _parser = const PartialJsonParser(),

  /// Applies `StateDelta` patches to the shared state.
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  /// Creates a mapper.
  this;

  /// Applies an AG-UI [event] to [state] and returns the resulting state.
  ///
  /// Doesn't touch `isRunning`: the client sets it for a whole turn, which
  /// spans several runs and the tool handlers between them.
  ///
  /// Pure: no I/O, no clocks, and [state] is never mutated. Events that
  /// don't change the agent return [state] itself.
  CopilotAgentState call(CopilotAgentState state, ag_ui.BaseEvent event) {
    return switch (event) {
      ag_ui.RunStartedEvent() => state.copyWith(error: () => null),
      ag_ui.RunFinishedEvent() => state.toolCallsMarkedExecuting(),
      ag_ui.RunErrorEvent(:final message, :final code) => state.copyWith(
        error: () => RunError(message: message, code: code),
      ),
      ag_ui.TextMessageStartEvent(:final messageId, :final role, :final name) =>
        state.messageAdded(
          Message.fromRole(role, id: messageId, content: '', name: name),
        ),
      ag_ui.TextMessageContentEvent(:final messageId, :final delta) =>
        state.textAppended(messageId, ag_ui.TextMessageRole.assistant, delta),
      ag_ui.TextMessageChunkEvent(
        :final messageId,
        :final role,
        :final delta,
      ) =>
        state.chunkAppended(messageId, role, delta ?? ''),
      ag_ui.ToolCallStartEvent(
        :final toolCallId,
        :final toolCallName,
        :final parentMessageId,
      ) =>
        state.toolCallStarted(toolCallId, toolCallName, parentMessageId),
      ag_ui.ToolCallArgsEvent(:final toolCallId, :final delta) =>
        _appendToolArgs(state, toolCallId, delta),
      ag_ui.ToolCallEndEvent(:final toolCallId) => state.toolCallUpdated(
        toolCallId,
        (view) => view.markedExecuting(),
      ),
      ag_ui.ToolCallChunkEvent() => _applyToolChunk(state, event),
      ag_ui.ToolCallResultEvent(
        :final messageId,
        :final toolCallId,
        :final content,
      ) =>
        state.toolCallCompleted(messageId, toolCallId, content),
      // Shared state is always a JSON object, so a snapshot of any other
      // JSON value is dropped, like a delta that doesn't apply.
      ag_ui.StateSnapshotEvent(snapshot: null) => state.sharedStateReplaced(
        null,
      ),
      ag_ui.StateSnapshotEvent(snapshot: final Map<String, Object?> json) =>
        state.sharedStateReplaced(json),
      ag_ui.StateDeltaEvent() => _applyStateDelta(state, event),
      ag_ui.MessagesSnapshotEvent(:final messages) => replaceMessages(state, [
        for (final message in messages) Message.fromAgUi(message),
      ]),
      _ => state,
    };
  }

  /// [state] with [messages] as its conversation, and its tool calls
  /// rebuilt from them; see [CopilotAgentState.messagesReplaced]. Calls
  /// that only exist in [messages] get the arguments parsed from their raw
  /// JSON.
  CopilotAgentState replaceMessages(
    CopilotAgentState state,
    List<Message> messages,
  ) => state.messagesReplaced(
    messages,
    argsOf: (call) => Map.unmodifiable(_parser.parse(call.arguments)),
  );

  /// Appends [delta] to the raw arguments of the tool call [toolCallId] and
  /// parses them for its view.
  CopilotAgentState _appendToolArgs(
    CopilotAgentState state,
    String toolCallId,
    String delta,
  ) {
    final call = state.messageToolCalls
        .where((call) => call.id == toolCallId)
        .lastOrNull;
    if (call == null) return state;
    final arguments = call.arguments + delta;
    return state.toolArgumentsReplaced(
      toolCallId,
      arguments,
      Map.unmodifiable(_parser.parse(arguments)),
    );
  }

  /// Applies a tool call chunk: it starts the call when it is new, then
  /// appends its arguments. A chunk without an id continues the last call.
  CopilotAgentState _applyToolChunk(
    CopilotAgentState state,
    ag_ui.ToolCallChunkEvent event,
  ) {
    final id = event.toolCallId ?? state.toolCalls.lastOrNull?.id;
    if (id == null) return state;
    var next = state;
    if (!next.toolCallsById.containsKey(id)) {
      final name = event.toolCallName;
      if (name == null) return state;
      next = next.toolCallStarted(id, name, event.parentMessageId);
    }
    final delta = event.delta;
    return delta == null ? next : _appendToolArgs(next, id, delta);
  }

  /// Patches the shared state with the delta of [event].
  ///
  /// A delta that doesn't apply (e.g. it was computed against a state this
  /// client never saw) is dropped; the next snapshot resyncs the state.
  /// Before any state exists the delta applies to an empty object, as in the
  /// AG-UI client, instead of being dropped.
  CopilotAgentState _applyStateDelta(
    CopilotAgentState state,
    ag_ui.StateDeltaEvent event,
  ) {
    try {
      return state.sharedStateReplaced(
        _patcher.apply(state.sharedState?.toJson() ?? const {}, event.delta),
      );
    } on FormatException {
      return state;
    }
  }
}
