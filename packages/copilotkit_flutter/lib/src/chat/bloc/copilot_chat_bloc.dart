import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/models/chat_row.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_chat_event.dart';
part 'copilot_chat_state.dart';

/// Drives a chat UI from a [CopilotAgent].
///
/// Mirrors the agent's state into [CopilotChatState] once
/// [ChatSubscriptionRequested] is added, and turns [ChatMessageSent] and
/// [ChatStopRequested] into [CopilotKitBloc] events.
class CopilotChatBloc({
  required final CopilotKitBloc _client,
  required final CopilotAgent _agent,
}) extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// Creates a bloc that drives a chat UI from [_agent], an agent opened on
  /// [_client].
  this : super(CopilotChatState.fromAgentState(_agent.state)) {
    on<ChatSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<ChatMessageSent>(_onMessageSent);
    on<ChatStopRequested>(_onStopRequested);
  }

  Future<void> _onSubscriptionRequested(
    ChatSubscriptionRequested event,
    Emitter<CopilotChatState> emit,
  ) async {
    // The agent may have changed since this bloc was created. Bloc emits
    // the first state even when it equals the initial one; skip that.
    final current = CopilotChatState.fromAgentState(_agent.state);
    if (current != state) emit(current);
    await emit.forEach(_agent.stream, onData: CopilotChatState.fromAgentState);
  }

  void _onMessageSent(ChatMessageSent event, Emitter<CopilotChatState> emit) {
    final text = event.text.trim();
    if (text.isEmpty) return;
    // The client drops the run, message included, when the agent is
    // already running.
    _client.add(
      AgentRunRequested(
        _agent.state.agentId,
        message: UserMessage(id: const Uuid().v4(), content: text),
      ),
    );
  }

  void _onStopRequested(
    ChatStopRequested event,
    Emitter<CopilotChatState> emit,
  ) {
    _client.add(AgentStopRequested(_agent.state.agentId));
  }
}
