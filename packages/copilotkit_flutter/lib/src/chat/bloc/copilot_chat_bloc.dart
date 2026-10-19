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
/// Mirrors `agent.stream` into [CopilotChatState] once
/// [ChatSubscriptionRequested] is added, and turns [ChatMessageSent] and
/// [ChatStopRequested] into agent calls.
class CopilotChatBloc({required final CopilotAgent _agent})
    extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// Creates a bloc that drives a chat UI from [_agent].
  this : super(CopilotChatState.fromAgentState(_agent.state)) {
    on<ChatSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    // One send at a time: a send that arrives while another is adding its
    // message would pass the isRunning check before the first run starts.
    on<ChatMessageSent>(_onMessageSent, transformer: droppable());
    on<ChatStopRequested>((_, _) => _agent.stop());
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

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<CopilotChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty || _agent.state.isRunning) return;
    await _agent.addMessage(UserMessage(id: const Uuid().v4(), content: text));
    _agent.run();
  }
}
