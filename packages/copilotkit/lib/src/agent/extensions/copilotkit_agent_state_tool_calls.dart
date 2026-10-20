import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';
import 'package:copilotkit/src/tools/tools.dart';

/// Edits the tool calls of a [CopilotKitAgentState].
extension CopilotKitAgentStateToolCalls on CopilotKitAgentState {
  /// Returns this state with the view of call [toolCallId] replaced by
  /// [update]'s result.
  ///
  /// Returns an equal state when there's no such call or [update] doesn't
  /// change it.
  CopilotKitAgentState updateToolCall(
    String toolCallId,
    ToolCallView Function(ToolCallView view) update,
  ) {
    final index = toolCalls.indexWhere((view) => view.id == toolCallId);
    if (index == -1) return this;
    final view = toolCalls[index];
    final updated = update(view);
    if (updated == view) return this;
    return copyWith(toolCalls: [...toolCalls]..[index] = updated);
  }
}
