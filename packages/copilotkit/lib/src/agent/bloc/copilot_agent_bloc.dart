import 'dart:async';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:copilotkit/src/agent/agent_event_reducer.dart';
import 'package:copilotkit/src/agent/models/copilot_agent_state.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

part 'copilot_agent_event.dart';

/// A conversation with one agent on a Copilot Runtime.
///
/// Holds the messages, shared state and tool calls of a thread as its
/// [state], and emits a new [CopilotAgentState] every time an event changes
/// it. Open one by adding `AgentOpened` to a `CopilotKitBloc` and read it
/// from `CopilotKitState.agents`.
class CopilotAgentBloc({
  required String agentId,
  String? threadId,
  final AgentEventReducer _reducer = const AgentEventReducer(),
}) extends Bloc<CopilotAgentEvent, CopilotAgentState> {
  /// Creates the agent [agentId].
  ///
  /// Internal: only the client creates agents, on `AgentOpened`, so it
  /// tracks every agent it runs. A random [threadId] is generated when none
  /// is given. The reducer applies AG-UI events to the state.
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
      AgentEventReceived(:final event) => _reducer.reduce(state, event),
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
}
