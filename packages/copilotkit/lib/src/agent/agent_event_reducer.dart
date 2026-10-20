import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:copilotkit/src/agent/models/shared_state.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:json_utils/json_utils.dart';

/// Applies AG-UI events to a [CopilotAgentState].
class const AgentEventReducer({
  /// Parses the streamed arguments of tool calls.
  final PartialJsonParser _parser = const PartialJsonParser(),

  /// Applies `StateDelta` patches to the shared state.
  final JsonPatcher _patcher = const JsonPatcher(),
}) {
  /// Creates a reducer.
  this;

  /// Applies an AG-UI [event] to [snapshot] and returns the resulting state.
  ///
  /// Doesn't touch `isRunning`: the client sets it for a whole turn, which
  /// spans several runs and the tool handlers between them.
  ///
  /// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
  /// don't change the agent return [snapshot] itself.
  CopilotAgentState reduce(CopilotAgentState snapshot, BaseEvent event) {
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
        sharedState: () => SharedState(state),
      ),
      StateDeltaEvent() => _applyStateDelta(snapshot, event),
      MessagesSnapshotEvent(:final messages) => _replaceMessages(
        snapshot,
        messages,
      ),
      _ => snapshot,
    };
  }

  /// [snapshot] with [messages] as its conversation, and its tool calls
  /// rebuilt from them, so calls that only exist in [messages] (a loaded
  /// history, a resync) render like live ones.
  CopilotAgentState _replaceMessages(
    CopilotAgentState snapshot,
    List<Message> messages,
  ) => snapshot.copyWith(
    messages: messages,
    toolCalls: _toolCallsOf(messages, snapshot.toolCalls),
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
        for (final call in message.toolCalls ?? const <ToolCall>[])
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
          name: call.function.name,
          status: ToolCallStatus.executing,
          args: JsonObject(_parser.parse(call.function.arguments)),
        );
    return switch (results[call.id]) {
      final result? => view.copyWith(
        status: ToolCallStatus.complete,
        result: () => result,
        awaitingResponse: false,
      ),
      null => view,
    };
  }

  /// A delta that doesn't apply (e.g. it was computed against a state this
  /// client never saw) is dropped; the next snapshot resyncs the state.
  ///
  /// Before any state exists the delta applies to an empty object, as in the
  /// AG-UI client, instead of being dropped. A state that isn't a JSON
  /// object can't be patched, so the delta is dropped too.
  CopilotAgentState _applyStateDelta(
    CopilotAgentState snapshot,
    StateDeltaEvent event,
  ) {
    try {
      return snapshot.copyWith(
        sharedState: () => SharedState(
          _patcher.apply(_documentOf(snapshot.sharedState), event.delta),
        ),
      );
    } on FormatException {
      return snapshot;
    }
  }

  /// The JSON object [state] holds, or an empty one when there is none.
  ///
  /// Throws a [FormatException] when [state] isn't a JSON object.
  Map<String, Object?> _documentOf(SharedState? state) =>
      switch (state?.toJson()) {
        null => const {},
        final Map<String, Object?> document => document,
        final value => throw FormatException(
          'Shared state is not a JSON object: $value',
        ),
      };

  CopilotAgentState _startToolCall(
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

  CopilotAgentState _appendToolArgs(
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
    final args = JsonObject(_parser.parse(arguments));
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
  List<Message> _replaceToolCall(
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
              // ag_ui models don't override `==`, so this matches the
              // ToolCall itself, not another one with the same fields.
              if (c == call) replacement else c,
          ],
        )
      else
        message,
  ];

  CopilotAgentState _applyToolChunk(
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

  CopilotAgentState _completeToolCall(
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
      (view) => view.copyWith(
        status: ToolCallStatus.complete,
        result: () => content,
        awaitingResponse: false,
      ),
    );
  }

  /// Calls streamed as chunks have no End event; once the run finishes their
  /// arguments are complete.
  CopilotAgentState _finishToolArgs(CopilotAgentState snapshot) {
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

  CopilotAgentState _updateToolCall(
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
  CopilotAgentState _appendChunk(
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

  TextMessageRole? _roleOf(Message message) => switch (message) {
    AssistantMessage() => TextMessageRole.assistant,
    UserMessage() => TextMessageRole.user,
    SystemMessage() => TextMessageRole.system,
    DeveloperMessage() => TextMessageRole.developer,
    _ => null,
  };

  /// Appends [delta] to message [messageId], creating it with [role] when it
  /// doesn't exist yet.
  CopilotAgentState _appendText(
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

  Message _textMessage(
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
  Message _withText(Message message, String text) {
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
