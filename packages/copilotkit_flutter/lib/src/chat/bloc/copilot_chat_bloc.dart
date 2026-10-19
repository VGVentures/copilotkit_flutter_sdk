import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/models/chat_row.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_chat_event.dart';
part 'copilot_chat_state.dart';

/// Drives a chat UI from a [CopilotAgent].
///
/// Mirrors `agent.stream` into [CopilotChatState] and turns
/// [ChatMessageSent] and [ChatStopRequested] into agent calls.
class CopilotChatBloc({required final CopilotAgent _agent})
    extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// Creates a bloc that drives a chat UI from [_agent].
  this : super(CopilotChatState.fromAgentState(_agent.state)) {
    on<_AgentStateChanged>(
      (event, emit) => emit(CopilotChatState.fromAgentState(event.state)),
    );
    on<ChatMessageSent>(_onMessageSent);
    on<ChatStopRequested>((_, _) => _agent.stop());
    _subscription = _agent.stream.listen(
      (state) => add(_AgentStateChanged(state)),
    );
  }

  late final StreamSubscription<AgentState> _subscription;

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<CopilotChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty || _agent.state.isRunning) return;
    await _agent.addMessage(UserMessage(id: const Uuid().v4(), content: text));
    _agent.run();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return await super.close();
  }
}
