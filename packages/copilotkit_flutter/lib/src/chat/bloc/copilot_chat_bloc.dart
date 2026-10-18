import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/models/chat_row.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

part 'copilot_chat_event.dart';
part 'copilot_chat_state.dart';

/// {@template copilot_chat_bloc}
/// Drives a chat UI from a [CopilotAgent].
///
/// Mirrors `agent.stream` into [CopilotChatState] and turns
/// [ChatMessageSent] and [ChatStopRequested] into agent calls.
/// {@endtemplate}
class CopilotChatBloc({required final CopilotAgent _agent})
    extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// {@macro copilot_chat_bloc}
  this : super(CopilotChatState.fromAgentState(_agent.state)) {
    on<_AgentStateChanged>(
      (event, emit) => emit(CopilotChatState.fromAgentState(event.state)),
    );
    // A send lasts until its turn ends, so one that arrives meanwhile is
    // dropped, as the event documents, even before the agent reports that
    // it is running.
    on<ChatMessageSent>(_onMessageSent, transformer: droppable());
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
    await _agent.run();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return await super.close();
  }
}
