import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/run_error.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:copilotkit/src/tools/tools.dart';
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
      ag_ui.RunFinishedEvent() => _finishToolArgs(state),
      ag_ui.RunErrorEvent(:final message, :final code) => state.copyWith(
        error: () => RunError(message: message, code: code),
      ),
      ag_ui.TextMessageStartEvent(:final messageId, :final role, :final name) =>
        state.copyWith(
          messages: [
            ...state.messages,
            _textMessage(messageId, role, name, ''),
          ],
        ),
      ag_ui.TextMessageContentEvent(:final messageId, :final delta) =>
        _appendText(state, messageId, ag_ui.TextMessageRole.assistant, delta),
      ag_ui.TextMessageChunkEvent(
        :final messageId,
        :final role,
        :final delta,
      ) =>
        _appendChunk(state, messageId, role, delta ?? ''),
      ag_ui.ToolCallStartEvent(
        :final toolCallId,
        :final toolCallName,
        :final parentMessageId,
      ) =>
        _startToolCall(state, toolCallId, toolCallName, parentMessageId),
      ag_ui.ToolCallArgsEvent(:final toolCallId, :final delta) =>
        _appendToolArgs(state, toolCallId, delta),
      ag_ui.ToolCallEndEvent(:final toolCallId) => _updateToolCall(
        state,
        toolCallId,
        (view) => view.markedExecuting(),
      ),
      ag_ui.ToolCallChunkEvent() => _applyToolChunk(state, event),
      ag_ui.ToolCallResultEvent(
        :final messageId,
        :final toolCallId,
        :final content,
      ) =>
        _completeToolCall(state, messageId, toolCallId, content),
      ag_ui.StateSnapshotEvent(snapshot: final json) => _replaceState(
        state,
        json,
      ),
      ag_ui.StateDeltaEvent() => _applyStateDelta(state, event),
      ag_ui.MessagesSnapshotEvent(:final messages) => replaceMessages(state, [
        for (final message in messages) Message.fromAgUi(message),
      ]),
      _ => state,
    };
  }

  /// [state] with [messages] as its conversation, and its tool calls
  /// rebuilt from them, so calls that only exist in [messages] (a loaded
  /// history, a resync) render like live ones.
  CopilotAgentState replaceMessages(
    CopilotAgentState state,
    List<Message> messages,
  ) => state.copyWith(
    messages: messages,
    toolCalls: _toolCallsOf(messages, state.toolCalls),
  );

  /// The tool calls held by the assistant messages in [messages], in order.
  ///
  /// A call with a tool message is complete, with the message's content as
  /// its result. A call without one keeps its view in [known] (it is still
  /// streaming or executing); one that isn't known has its full arguments,
  /// so it is executing. Views in [known] that no message holds anymore are
  /// dropped.
  List<ToolCallView> _toolCallsOf(
    List<Message> messages,
    List<ToolCallView> known,
  ) {
    final results = {
      for (final message in messages.whereType<ToolMessage>())
        message.toolCallId: message.content,
    };
    final knownById = {for (final view in known) view.id: view};
    return [
      for (final message in messages.whereType<AssistantMessage>())
        for (final call in message.toolCalls)
          _viewOf(call, knownById[call.id], results),
    ];
  }

  ToolCallView _viewOf(
    ToolCall call,
    ToolCallView? known,
    Map<String, String> results,
  ) {
    final view =
        known ??
        ToolCallView(
          id: call.id,
          name: call.name,
          status: ToolCallStatus.executing,
          args: Map.unmodifiable(_parser.parse(call.arguments)),
        );
    return switch (results[call.id]) {
      final result? => view.completed(result),
      null => view,
    };
  }

  /// A delta that doesn't apply (e.g. it was computed against a state this
  /// client never saw) is dropped; the next snapshot resyncs the state.
  ///
  /// Before any state exists the delta applies to an empty object, as in the
  /// AG-UI client, instead of being dropped.
  CopilotAgentState _applyStateDelta(
    CopilotAgentState state,
    ag_ui.StateDeltaEvent event,
  ) {
    try {
      return state.copyWith(
        sharedState: () => SharedState(
          Map.unmodifiable(
            _patcher.apply(
              state.sharedState?.toJson() ?? const {},
              event.delta,
            ),
          ),
        ),
      );
    } on FormatException {
      return state;
    }
  }

  /// [state] with the shared state replaced by [json], or cleared when
  /// [json] is `null`.
  ///
  /// Shared state is always a JSON object, so a snapshot of any other JSON
  /// value is dropped, like a delta that doesn't apply.
  CopilotAgentState _replaceState(CopilotAgentState state, Object? json) =>
      switch (json) {
        null => state.copyWith(sharedState: () => null),
        final Map<String, Object?> json => state.copyWith(
          sharedState: () => SharedState(Map.unmodifiable(json)),
        ),
        _ => state,
      };

  CopilotAgentState _startToolCall(
    CopilotAgentState state,
    String toolCallId,
    String name,
    String? parentMessageId,
  ) {
    if (state.toolCalls.any((view) => view.id == toolCallId)) {
      return state;
    }
    final call = ToolCall(id: toolCallId, name: name, arguments: '');
    final messages = state.messages;
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
        parent.copyWith(toolCalls: [...parent.toolCalls, call]),
        ...messages.sublist(parentIndex + 1),
      ];
    }
    return state.copyWith(
      messages: nextMessages,
      toolCalls: [
        ...state.toolCalls,
        ToolCallView(
          id: toolCallId,
          name: name,
          status: ToolCallStatus.inProgress,
        ),
      ],
    );
  }

  CopilotAgentState _appendToolArgs(
    CopilotAgentState state,
    String toolCallId,
    String delta,
  ) {
    final call = state.messages
        .whereType<AssistantMessage>()
        .expand((message) => message.toolCalls)
        .where((call) => call.id == toolCallId)
        .lastOrNull;
    if (call == null) return state;
    final arguments = call.arguments + delta;
    final updatedCall = call.copyWith(arguments: arguments);
    final args = Map<String, Object?>.unmodifiable(_parser.parse(arguments));
    return _updateToolCall(
      state.copyWith(messages: _replaceToolCall(state.messages, updatedCall)),
      toolCallId,
      (view) => view.copyWith(args: args),
    );
  }

  /// [messages] with the call that has the id of [replacement] replaced by
  /// it, in the assistant message that holds it.
  ///
  /// Matches by id: `_startToolCall` drops a repeated id, so no two calls
  /// share one.
  List<Message> _replaceToolCall(
    List<Message> messages,
    ToolCall replacement,
  ) => [
    for (final message in messages)
      if (message is AssistantMessage &&
          message.toolCalls.any((c) => c.id == replacement.id))
        message.copyWith(
          toolCalls: [
            for (final c in message.toolCalls)
              if (c.id == replacement.id) replacement else c,
          ],
        )
      else
        message,
  ];

  CopilotAgentState _applyToolChunk(
    CopilotAgentState state,
    ag_ui.ToolCallChunkEvent event,
  ) {
    final id = event.toolCallId ?? state.toolCalls.lastOrNull?.id;
    if (id == null) return state;
    var next = state;
    if (!next.toolCalls.any((view) => view.id == id)) {
      final name = event.toolCallName;
      if (name == null) return state;
      next = _startToolCall(next, id, name, event.parentMessageId);
    }
    final delta = event.delta;
    return delta == null ? next : _appendToolArgs(next, id, delta);
  }

  CopilotAgentState _completeToolCall(
    CopilotAgentState state,
    String messageId,
    String toolCallId,
    String content,
  ) {
    if (state.messages.any((m) => m is ToolMessage && m.id == messageId)) {
      return state;
    }
    return _updateToolCall(
      state.copyWith(
        messages: [
          ...state.messages,
          ToolMessage(id: messageId, toolCallId: toolCallId, content: content),
        ],
      ),
      toolCallId,
      (view) => view.completed(content),
    );
  }

  /// Calls streamed as chunks have no End event; once the run finishes their
  /// arguments are complete.
  CopilotAgentState _finishToolArgs(CopilotAgentState state) {
    if (!state.toolCalls.any((view) => view.isInProgress)) {
      return state;
    }
    return state.copyWith(
      toolCalls: [for (final view in state.toolCalls) view.markedExecuting()],
    );
  }

  CopilotAgentState _updateToolCall(
    CopilotAgentState state,
    String toolCallId,
    ToolCallView Function(ToolCallView view) update,
  ) {
    final index = state.toolCalls.indexWhere((view) => view.id == toolCallId);
    if (index == -1) return state;
    final view = state.toolCalls[index];
    final updated = update(view);
    if (updated == view) return state;
    return state.copyWith(
      toolCalls: [
        ...state.toolCalls.sublist(0, index),
        updated,
        ...state.toolCalls.sublist(index + 1),
      ],
    );
  }

  /// A chunk without [messageId] continues the last message, but only when it
  /// has the chunk's role, so assistant text never lands in a user message.
  CopilotAgentState _appendChunk(
    CopilotAgentState state,
    String? messageId,
    ag_ui.TextMessageRole? role,
    String delta,
  ) {
    final chunkRole = role ?? ag_ui.TextMessageRole.assistant;
    final last = state.messages.lastOrNull;
    final id =
        messageId ??
        (last != null && _roleOf(last) == chunkRole ? last.id : null);
    if (id == null) return state;
    return _appendText(state, id, chunkRole, delta);
  }

  ag_ui.TextMessageRole? _roleOf(Message message) => switch (message) {
    AssistantMessage() => ag_ui.TextMessageRole.assistant,
    UserMessage() => ag_ui.TextMessageRole.user,
    SystemMessage() => ag_ui.TextMessageRole.system,
    DeveloperMessage() => ag_ui.TextMessageRole.developer,
    _ => null,
  };

  /// Appends [delta] to message [messageId], creating it with [role] when it
  /// doesn't exist yet.
  CopilotAgentState _appendText(
    CopilotAgentState state,
    String messageId,
    ag_ui.TextMessageRole role,
    String delta,
  ) {
    final messages = state.messages;
    final index = messages.lastIndexWhere((m) => m.id == messageId);
    if (index == -1) {
      return state.copyWith(
        messages: [...messages, _textMessage(messageId, role, null, delta)],
      );
    }
    return state.copyWith(
      messages: [
        ...messages.sublist(0, index),
        _withDelta(messages[index], delta),
        ...messages.sublist(index + 1),
      ],
    );
  }

  Message _textMessage(
    String id,
    ag_ui.TextMessageRole role,
    String? name,
    String text,
  ) {
    return switch (role) {
      ag_ui.TextMessageRole.assistant => AssistantMessage(
        id: id,
        content: text,
        name: name,
      ),
      ag_ui.TextMessageRole.user => UserMessage(
        id: id,
        content: text,
        name: name,
      ),
      ag_ui.TextMessageRole.system => SystemMessage(
        id: id,
        content: text,
        name: name,
      ),
      ag_ui.TextMessageRole.developer => DeveloperMessage(
        id: id,
        content: text,
        name: name,
      ),
    };
  }

  /// Returns [message] with [delta] appended to its text.
  ///
  /// Only text messages are created by the mapper, so other message kinds
  /// are returned unchanged.
  Message _withDelta(Message message, String delta) {
    return switch (message) {
      AssistantMessage(:final content) => message.copyWith(
        content: () => '${content ?? ''}$delta',
      ),
      UserMessage(
        :final id,
        :final content,
        :final name,
        :final encryptedValue,
      ) =>
        UserMessage(
          id: id,
          content: '$content$delta',
          name: name,
          encryptedValue: encryptedValue,
        ),
      SystemMessage(
        :final id,
        :final content,
        :final name,
        :final encryptedValue,
      ) =>
        SystemMessage(
          id: id,
          content: '$content$delta',
          name: name,
          encryptedValue: encryptedValue,
        ),
      DeveloperMessage(
        :final id,
        :final content,
        :final name,
        :final encryptedValue,
      ) =>
        DeveloperMessage(
          id: id,
          content: '$content$delta',
          name: name,
          encryptedValue: encryptedValue,
        ),
      _ => message,
    };
  }
}
