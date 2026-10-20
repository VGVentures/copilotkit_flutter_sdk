import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/chat_row_mapper.dart';
import 'package:copilotkit_flutter/src/chat/models/chat_row.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_chat_event.dart';
part 'copilot_chat_state.dart';

/// Drives a chat UI from a [CopilotKitAgent].
///
/// Mirrors the agent's state into [CopilotChatState] once
/// [ChatSubscriptionRequested] is added, and turns [ChatMessageSent] and
/// [ChatStopRequested] into runs and stops on the [CopilotKitClient].
class CopilotChatBloc({
  required final CopilotKitClient _client,
  required String agentId,

  /// Maps the agent's messages to chat rows.
  final ChatRowMapper _rows = const ChatRowMapper(),
}) extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// Creates a bloc that drives a chat UI from the agent `agentId` of
  /// [_client], opening it if needed.
  this
    : super(
        CopilotChatState.fromAgentState(
          _client.agent(agentId).state,
          rows: _rows,
        ),
      ) {
    on<ChatSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<ChatMessageSent>(_onMessageSent);
    on<ChatStopRequested>(_onStopRequested);
  }

  final CopilotKitAgent _agent = _client.agent(agentId);

  Future<void> _onSubscriptionRequested(
    ChatSubscriptionRequested event,
    Emitter<CopilotChatState> emit,
  ) async {
    // The agent may have changed since this bloc was created. Bloc emits
    // the first state even when it equals the initial one; skip that.
    final current = CopilotChatState.fromAgentState(_agent.state, rows: _rows);
    if (current != state) emit(current);
    await emit.forEach(
      _agent.stream,
      onData: (state) => CopilotChatState.fromAgentState(state, rows: _rows),
    );
  }

  void _onMessageSent(ChatMessageSent event, Emitter<CopilotChatState> emit) {
    final text = event.text.trim();
    if (text.isEmpty) return;
    // The client drops the run, message included, when the agent is
    // already running. The turn reports to the agent's state, which this
    // bloc mirrors, so it isn't awaited.
    unawaited(
      _client.runAgent(
        _agent.state.agentId,
        message: UserMessage(id: const Uuid().v4(), content: text),
      ),
    );
  }

  void _onStopRequested(
    ChatStopRequested event,
    Emitter<CopilotChatState> emit,
  ) {
    unawaited(_client.stopAgent(_agent.state.agentId));
  }
}
