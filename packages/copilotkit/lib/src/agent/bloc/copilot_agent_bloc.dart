import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:copilotkit/src/json_patch.dart';
import 'package:copilotkit/src/partial_json_parser.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

part 'copilot_agent_event.dart';
part 'copilot_agent_state.dart';

/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread as its
/// [state], and emits a new [CopilotAgentState] every time an event changes
/// it. Open one by adding `AgentOpened` to a `CopilotKitBloc` and read it
/// from `CopilotKitState.agents`.
class CopilotAgentBloc({required String agentId, String? threadId})
    extends Bloc<CopilotAgentEvent, CopilotAgentState> {
  /// Creates the agent [agentId].
  ///
  /// Internal: only the client creates agents, on `AgentOpened`, so it
  /// tracks every agent it runs. A random [threadId] is generated when none
  /// is given.
  @internal
  this
    : super(
        CopilotAgentState(
          agentId: agentId,
          threadId: threadId ?? const Uuid().v4(),
        ),
      ) {
    // One handler for the whole family: the handlers are synchronous, so
    // events apply in the order they were added (ADR 0002).
    on<CopilotAgentEvent>(_onEvent);
  }

  void _onEvent(CopilotAgentEvent event, Emitter<CopilotAgentState> emit) {
    final next = switch (event) {
      AgentEventReceived(:final event) => _reduce(state, event),
      AgentMessageAdded(:final message) => state.copyWith(
        messages: [...state.messages, message],
      ),
      AgentTurnStarted() => state.copyWith(isRunning: true, error: () => null),
      AgentTurnEnded() => state.copyWith(isRunning: false),
      AgentRunFailed(:final error) => state.copyWith(error: () => error),
      AgentSettleRequested(:final completer) => _settle(completer),
    };
    // Bloc emits the first state even when it equals the initial one;
    // consumers only want changes.
    if (next == state) return;
    emit(next);
  }

  /// Completes [completer] and keeps the state: every event added before
  /// the [AgentSettleRequested] has been applied by now.
  CopilotAgentState _settle(Completer<void> completer) {
    completer.complete();
    return state;
  }

  /// Applies an AG-UI [event] to [snapshot] and returns the resulting state.
  ///
  /// Doesn't touch `isRunning`: the client sets it for a whole turn, which
  /// spans several runs and the tool handlers between them.
  ///
  /// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
  /// don't change the agent return [snapshot] itself.
  static CopilotAgentState _reduce(
    CopilotAgentState snapshot,
    BaseEvent event,
  ) {
    return switch (event) {
      RunStartedEvent() => snapshot.copyWith(error: () => null),
      RunFinishedEvent() => _finishToolArgs(snapshot),
      RunErrorEvent() => snapshot.copyWith(error: () => event),
      TextMessageStartEvent(:final messageId, :final role, :final name) =>
        snapshot.copyWith(
          messages: [
            ...snapshot.messages,
            _textMessage(messageId, role, name, ''),
          ],
        ),
      TextMessageContentEvent(:final messageId, :final delta) => _appendText(
        snapshot,
        messageId,
        TextMessageRole.assistant,
        delta,
      ),
      TextMessageChunkEvent(:final messageId, :final role, :final delta) =>
        _appendChunk(snapshot, messageId, role, delta ?? ''),
      ToolCallStartEvent(
        :final toolCallId,
        :final toolCallName,
        :final parentMessageId,
      ) =>
        _startToolCall(snapshot, toolCallId, toolCallName, parentMessageId),
      ToolCallArgsEvent(:final toolCallId, :final delta) => _appendToolArgs(
        snapshot,
        toolCallId,
        delta,
      ),
      ToolCallEndEvent(:final toolCallId) => _updateToolCall(
        snapshot,
        toolCallId,
        (view) => view.status == ToolCallStatus.inProgress
            ? view.copyWith(status: ToolCallStatus.executing)
            : view,
      ),
      ToolCallChunkEvent() => _applyToolChunk(snapshot, event),
      ToolCallResultEvent(
        :final messageId,
        :final toolCallId,
        :final content,
      ) =>
        _completeToolCall(snapshot, messageId, toolCallId, content),
      StateSnapshotEvent(snapshot: final state) => snapshot.copyWith(
        sharedState: () => state,
      ),
      StateDeltaEvent(:final delta) => _applyStateDelta(snapshot, delta),
      MessagesSnapshotEvent(:final messages) => snapshot.copyWith(
        messages: messages,
      ),
      _ => snapshot,
    };
  }

  /// A delta that doesn't apply (e.g. it was computed against a state this
  /// client never saw) is dropped; the next snapshot resyncs the state.
  static CopilotAgentState _applyStateDelta(
    CopilotAgentState snapshot,
    List<Map<String, Object?>> delta,
  ) {
    try {
      return snapshot.copyWith(
        sharedState: () => JsonPatch.apply(snapshot.sharedState, delta),
      );
    } on FormatException {
      return snapshot;
    }
  }

  static CopilotAgentState _startToolCall(
    CopilotAgentState snapshot,
    String toolCallId,
    String name,
    String? parentMessageId,
  ) {
    if (snapshot.toolCalls.any((view) => view.id == toolCallId)) {
      return snapshot;
    }
    final call = ToolCall(
      id: toolCallId,
      function: FunctionCall(name: name, arguments: ''),
    );
    final messages = snapshot.messages;
    final parentIndex = parentMessageId == null
        ? -1
        : messages.lastIndexWhere(
            (m) => m is AssistantMessage && m.id == parentMessageId,
          );
    final List<Message> nextMessages;
    if (parentIndex == -1) {
      nextMessages = [
        ...messages,
        AssistantMessage(id: parentMessageId ?? toolCallId, toolCalls: [call]),
      ];
    } else {
      final parent = messages[parentIndex] as AssistantMessage;
      nextMessages = [
        ...messages.sublist(0, parentIndex),
        parent.copyWith(toolCalls: [...?parent.toolCalls, call]),
        ...messages.sublist(parentIndex + 1),
      ];
    }
    return snapshot.copyWith(
      messages: nextMessages,
      toolCalls: [
        ...snapshot.toolCalls,
        ToolCallView(
          id: toolCallId,
          name: name,
          status: ToolCallStatus.inProgress,
        ),
      ],
    );
  }

  static CopilotAgentState _appendToolArgs(
    CopilotAgentState snapshot,
    String toolCallId,
    String delta,
  ) {
    final call = snapshot.messages
        .whereType<AssistantMessage>()
        .expand((message) => message.toolCalls ?? const <ToolCall>[])
        .where((call) => call.id == toolCallId)
        .lastOrNull;
    if (call == null) return snapshot;
    final arguments = call.function.arguments + delta;
    final updatedCall = call.copyWith(
      function: call.function.copyWith(arguments: arguments),
    );
    final args = PartialJsonParser.parse(arguments);
    return _updateToolCall(
      snapshot.copyWith(
        messages: _replaceToolCall(snapshot.messages, call, updatedCall),
      ),
      toolCallId,
      (view) => view.copyWith(args: args),
    );
  }

  /// [messages] with [call] replaced by [replacement] in the assistant
  /// message that holds it.
  static List<Message> _replaceToolCall(
    List<Message> messages,
    ToolCall call,
    ToolCall replacement,
  ) => [
    for (final message in messages)
      if (message is AssistantMessage &&
          (message.toolCalls?.contains(call) ?? false))
        message.copyWith(
          toolCalls: [
            for (final c in message.toolCalls!)
              // The same ToolCall instance, not an equal one: ag_ui models
              // compare by identity.
              if (identical(c, call)) replacement else c,
          ],
        )
      else
        message,
  ];

  static CopilotAgentState _applyToolChunk(
    CopilotAgentState snapshot,
    ToolCallChunkEvent event,
  ) {
    final id = event.toolCallId ?? snapshot.toolCalls.lastOrNull?.id;
    if (id == null) return snapshot;
    var next = snapshot;
    if (!next.toolCalls.any((view) => view.id == id)) {
      final name = event.toolCallName;
      if (name == null) return snapshot;
      next = _startToolCall(next, id, name, event.parentMessageId);
    }
    final delta = event.delta;
    return delta == null ? next : _appendToolArgs(next, id, delta);
  }

  static CopilotAgentState _completeToolCall(
    CopilotAgentState snapshot,
    String messageId,
    String toolCallId,
    String content,
  ) {
    if (snapshot.messages.any((m) => m is ToolMessage && m.id == messageId)) {
      return snapshot;
    }
    return _updateToolCall(
      snapshot.copyWith(
        messages: [
          ...snapshot.messages,
          ToolMessage(id: messageId, toolCallId: toolCallId, content: content),
        ],
      ),
      toolCallId,
      (view) =>
          view.copyWith(status: ToolCallStatus.complete, result: () => content),
    );
  }

  /// Calls streamed as chunks have no End event; once the run finishes their
  /// arguments are complete.
  static CopilotAgentState _finishToolArgs(CopilotAgentState snapshot) {
    if (!snapshot.toolCalls.any((v) => v.status == ToolCallStatus.inProgress)) {
      return snapshot;
    }
    return snapshot.copyWith(
      toolCalls: [
        for (final view in snapshot.toolCalls)
          if (view.status == ToolCallStatus.inProgress)
            view.copyWith(status: ToolCallStatus.executing)
          else
            view,
      ],
    );
  }

  static CopilotAgentState _updateToolCall(
    CopilotAgentState snapshot,
    String toolCallId,
    ToolCallView Function(ToolCallView view) update,
  ) {
    final index = snapshot.toolCalls.indexWhere(
      (view) => view.id == toolCallId,
    );
    if (index == -1) return snapshot;
    final view = snapshot.toolCalls[index];
    final updated = update(view);
    if (updated == view) return snapshot;
    return snapshot.copyWith(
      toolCalls: [
        ...snapshot.toolCalls.sublist(0, index),
        updated,
        ...snapshot.toolCalls.sublist(index + 1),
      ],
    );
  }

  /// A chunk without [messageId] continues the last message, but only when it
  /// has the chunk's role, so assistant text never lands in a user message.
  static CopilotAgentState _appendChunk(
    CopilotAgentState snapshot,
    String? messageId,
    TextMessageRole? role,
    String delta,
  ) {
    final chunkRole = role ?? TextMessageRole.assistant;
    final last = snapshot.messages.lastOrNull;
    final id =
        messageId ??
        (last != null && _roleOf(last) == chunkRole ? last.id : null);
    if (id == null) return snapshot;
    return _appendText(snapshot, id, chunkRole, delta);
  }

  static TextMessageRole? _roleOf(Message message) => switch (message) {
    AssistantMessage() => TextMessageRole.assistant,
    UserMessage() => TextMessageRole.user,
    SystemMessage() => TextMessageRole.system,
    DeveloperMessage() => TextMessageRole.developer,
    _ => null,
  };

  /// Appends [delta] to message [messageId], creating it with [role] when it
  /// doesn't exist yet.
  static CopilotAgentState _appendText(
    CopilotAgentState snapshot,
    String messageId,
    TextMessageRole role,
    String delta,
  ) {
    final messages = snapshot.messages;
    final index = messages.lastIndexWhere((m) => m.id == messageId);
    if (index == -1) {
      return snapshot.copyWith(
        messages: [...messages, _textMessage(messageId, role, null, delta)],
      );
    }
    final message = messages[index];
    return snapshot.copyWith(
      messages: [
        ...messages.sublist(0, index),
        _withText(message, '${message.content ?? ''}$delta'),
        ...messages.sublist(index + 1),
      ],
    );
  }

  static Message _textMessage(
    String id,
    TextMessageRole role,
    String? name,
    String text,
  ) {
    return switch (role) {
      TextMessageRole.assistant => AssistantMessage(
        id: id,
        content: text,
        name: name,
      ),
      TextMessageRole.user => UserMessage(id: id, content: text, name: name),
      TextMessageRole.system => SystemMessage(
        id: id,
        content: text,
        name: name,
      ),
      TextMessageRole.developer => DeveloperMessage(
        id: id,
        content: text,
        name: name,
      ),
    };
  }

  /// Returns [message] with its text replaced by [text].
  ///
  /// Only text messages are created by the reducer, so other message kinds
  /// are returned unchanged.
  static Message _withText(Message message, String text) {
    return switch (message) {
      AssistantMessage() => message.copyWith(content: text),
      UserMessage(:final id, :final name) => UserMessage(
        id: id,
        content: text,
        name: name,
      ),
      SystemMessage(:final id, :final name) => SystemMessage(
        id: id,
        content: text,
        name: name,
      ),
      DeveloperMessage(:final id, :final name) => DeveloperMessage(
        id: id,
        content: text,
        name: name,
      ),
      _ => message,
    };
  }
}
