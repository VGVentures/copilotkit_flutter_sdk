import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/mappers/text_message_mapper.dart';
import 'package:copilotkit/src/agent/mappers/tool_call_mapper.dart';
import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/json/json.dart';

/// Applies AG-UI events to a [CopilotKitAgentState].
class const AgentEventMapper({
  /// Applies text message events.
  final TextMessageMapper _text = const TextMessageMapper(),

  /// Applies tool call events.
  final ToolCallMapper _toolCalls = const ToolCallMapper(),

  /// Applies `StateDelta` patches to the shared state.
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  /// Creates a mapper.
  this;

  /// Applies an AG-UI [event] to [snapshot] and returns the resulting state.
  ///
  /// Doesn't touch `isRunning`: the client sets it for a whole turn, which
  /// spans several runs and the tool handlers between them.
  ///
  /// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
  /// don't change the agent return [snapshot] itself.
  CopilotKitAgentState call(CopilotKitAgentState snapshot, BaseEvent event) {
    return switch (event) {
      RunStartedEvent() => snapshot.copyWith(error: () => null),
      RunFinishedEvent() => _toolCalls.finishArgs(snapshot),
      RunErrorEvent() => snapshot.copyWith(error: () => event),
      TextMessageStartEvent(:final messageId, :final role, :final name) =>
        _text.start(snapshot, messageId, role, name),
      TextMessageContentEvent(:final messageId, :final delta) => _text.append(
        snapshot,
        messageId,
        TextMessageRole.assistant,
        delta,
      ),
      TextMessageChunkEvent(:final messageId, :final role, :final delta) =>
        _text.appendChunk(snapshot, messageId, role, delta ?? ''),
      ToolCallStartEvent(
        :final toolCallId,
        :final toolCallName,
        :final parentMessageId,
      ) =>
        _toolCalls.start(snapshot, toolCallId, toolCallName, parentMessageId),
      ToolCallArgsEvent(:final toolCallId, :final delta) =>
        _toolCalls.appendArgs(snapshot, toolCallId, delta),
      ToolCallEndEvent(:final toolCallId) => _toolCalls.end(
        snapshot,
        toolCallId,
      ),
      ToolCallChunkEvent() => _toolCalls.applyChunk(snapshot, event),
      ToolCallResultEvent(
        :final messageId,
        :final toolCallId,
        :final content,
      ) =>
        _toolCalls.complete(snapshot, messageId, toolCallId, content),
      StateSnapshotEvent(snapshot: final state) => snapshot.copyWith(
        sharedState: () => SharedState(state),
      ),
      StateDeltaEvent() => _applyStateDelta(snapshot, event),
      MessagesSnapshotEvent(:final messages) => _toolCalls.replaceMessages(
        snapshot,
        messages,
      ),
      _ => snapshot,
    };
  }

  /// A delta that doesn't apply (e.g. it was computed against a state this
  /// client never saw) is dropped; the next snapshot resyncs the state.
  ///
  /// Before any state exists the delta applies to an empty object, as in the
  /// AG-UI client, instead of being dropped.
  CopilotKitAgentState _applyStateDelta(
    CopilotKitAgentState snapshot,
    StateDeltaEvent event,
  ) {
    try {
      final operations = event.delta.map(JsonPatchOperation.fromJson).toList();
      return snapshot.copyWith(
        sharedState: () => SharedState(
          _patcher.apply(
            snapshot.sharedState?.toJson() ?? const <String, Object?>{},
            operations,
          ),
        ),
      );
    } on FormatException {
      return snapshot;
    }
  }
}
