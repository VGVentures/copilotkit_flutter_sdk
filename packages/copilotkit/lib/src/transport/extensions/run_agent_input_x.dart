import 'package:ag_ui/ag_ui.dart';

/// Conversions on [RunAgentInput] used by the transport.
extension RunAgentInputX on RunAgentInput {
  /// Copies this input into the [SimpleRunAgentInput] that `ag_ui`'s client
  /// sends to the runtime, field for field.
  SimpleRunAgentInput toSimpleInput() {
    return SimpleRunAgentInput(
      threadId: threadId,
      runId: runId,
      parentRunId: parentRunId,
      state: state,
      messages: messages,
      tools: tools,
      context: context,
      forwardedProps: forwardedProps,
    );
  }
}
