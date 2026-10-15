import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:copilotkit/src/agent/copilot_agent_event.dart';
import 'package:copilotkit/src/agent/models/agent_state.dart';
import 'package:copilotkit/src/client/copilot_kit_client.dart';
import 'package:copilotkit/src/json_patch.dart';
import 'package:copilotkit/src/partial_json_parser.dart';
import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// {@template copilot_agent}
/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread as its
/// [state], and emits a new [AgentState] on [stream] every time an event
/// changes it. Get one with `CopilotKitClient.agent`.
/// {@endtemplate}
class CopilotAgent({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,
  required final CopilotKitClient _client,
  String? threadId,
}) extends Bloc<CopilotAgentEvent, AgentState> {
  /// {@macro copilot_agent}
  ///
  /// Prefer `CopilotKitClient.agent`, which caches agents by id. A random
  /// [threadId] is generated when none is given.
  this : super(const AgentState()) {
    // One handler for the whole family: the handlers are synchronous, so
    // events apply in the order they were added (ADR 0002).
    on<CopilotAgentEvent>(_onEvent);
  }

  final _stateChanges = StreamController<Object?>.broadcast();

  /// Events added and not yet applied, and who is waiting for that.
  int _pending = 0;
  Completer<void>? _settled;

  /// Id of the conversation thread sent with every run.
  final String threadId = threadId ?? const Uuid().v4();

  /// Current state of the agent.
  AgentState get snapshot => state;

  /// Conversation messages, oldest first.
  List<Message> get messages => state.messages;

  /// Whether the agent is working: from `run()` until the whole turn ends,
  /// including frontend tool handlers and the runs that follow them.
  bool get isRunning => state.isRunning;

  /// Tool calls made by the agent, in call order.
  List<ToolCallView> get toolCalls => state.toolCalls;

  /// Emits a new [AgentState] every time the agent changes.
  Stream<AgentState> get changes => stream;

  /// Emits the shared state every time it changes.
  Stream<Object?> get stateStream => _stateChanges.stream;

  /// Completes once every event added so far has been applied.
  ///
  /// Bloc delivers events asynchronously; the client awaits this before it
  /// reads [state] after adding events.
  @internal
  Future<void> get settled =>
      _pending == 0 ? Future.value() : (_settled ??= Completer<void>()).future;

  @override
  void add(CopilotAgentEvent event) {
    super.add(event);
    _pending++;
  }

  /// Appends [message] to the conversation without starting a run.
  Future<void> addMessage(Message message) async {
    add(AgentMessageAdded(message));
    await settled;
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

  @override
  Future<void> close() async {
    await _stateChanges.close();
    await super.close();
  }

  void _onEvent(CopilotAgentEvent event, Emitter<AgentState> emit) {
    try {
      final next = switch (event) {
        AgentEventReceived(:final event) => _reduce(state, event),
        AgentMessageAdded(:final message) => state.copyWith(
          messages: [...state.messages, message],
        ),
        AgentTurnStarted() => state.copyWith(
          isRunning: true,
          error: () => null,
        ),
        AgentTurnEnded() => state.copyWith(isRunning: false),
        AgentRunFailed(:final error) => state.copyWith(error: () => error),
      };
      // Bloc emits the first state even when it equals the initial one;
      // consumers only want changes.
      if (next == state) return;
      if (next.sharedState != state.sharedState) {
        _stateChanges.add(next.sharedState);
      }
      emit(next);
    } finally {
      if (--_pending == 0) {
        _settled?.complete();
        _settled = null;
      }
    }
  }

  /// Applies an AG-UI [event] to [snapshot] and returns the resulting state.
  ///
  /// Doesn't touch `isRunning`: the client sets it for a whole turn, which
  /// spans several runs and the tool handlers between them.
  ///
  /// Pure: no I/O, no clocks, and [snapshot] is never mutated. Events that
  /// don't change the agent return [snapshot] itself.
  static AgentState _reduce(AgentState snapshot, BaseEvent event) {
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
  static AgentState _applyStateDelta(
    AgentState snapshot,
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

  static AgentState _startToolCall(
    AgentState snapshot,
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

  static AgentState _appendToolArgs(
    AgentState snapshot,
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
    final messages = [
      for (final message in snapshot.messages)
        if (message is AssistantMessage &&
            (message.toolCalls?.contains(call) ?? false))
          message.copyWith(
            toolCalls: [
              for (final c in message.toolCalls!)
                // The same ToolCall instance, not an equal one: ag_ui models
                // compare by identity.
                if (identical(c, call)) updatedCall else c,
            ],
          )
        else
          message,
    ];
    final args = PartialJsonParser.parse(arguments);
    return _updateToolCall(
      snapshot.copyWith(messages: messages),
      toolCallId,
      (view) => view.copyWith(args: args),
    );
  }

  static AgentState _applyToolChunk(
    AgentState snapshot,
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

  static AgentState _completeToolCall(
    AgentState snapshot,
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
  static AgentState _finishToolArgs(AgentState snapshot) {
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

  static AgentState _updateToolCall(
    AgentState snapshot,
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
  static AgentState _appendChunk(
    AgentState snapshot,
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
  static AgentState _appendText(
    AgentState snapshot,
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
