import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:equatable/equatable.dart';

part 'copilot_chat_event.dart';
part 'copilot_chat_state.dart';

/// {@template copilot_chat_bloc}
/// Drives a chat UI from a [CopilotAgent].
///
/// Mirrors `agent.changes` into [CopilotChatState] and turns
/// [ChatMessageSent] and [ChatStopRequested] into agent calls.
/// {@endtemplate}
class CopilotChatBloc({required final CopilotAgent _agent})
    extends Bloc<CopilotChatEvent, CopilotChatState> {
  /// {@macro copilot_chat_bloc}
  this : super(CopilotChatState.fromSnapshot(_agent.snapshot)) {
    on<_ChatSnapshotChanged>(
      (event, emit) => emit(CopilotChatState.fromSnapshot(event.snapshot)),
    );
    on<ChatMessageSent>(_onMessageSent);
    on<ChatStopRequested>((_, _) => _agent.stop());
    _subscription = _agent.changes.listen(
      (snapshot) => add(_ChatSnapshotChanged(snapshot)),
    );
  }

  late final StreamSubscription<AgentSnapshot> _subscription;
  int _sentCount = 0;

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<CopilotChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty || _agent.isRunning) return;
    final id = 'user-${DateTime.now().microsecondsSinceEpoch}-${_sentCount++}';
    await _agent.addMessage(UserMessage(id: id, content: text));
    await _agent.run();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return await super.close();
  }
}
