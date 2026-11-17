import 'package:ag_ui/ag_ui.dart';

/// Copies a [RunAgentInput] into the [SimpleRunAgentInput] that `ag_ui` sends
/// to a runtime, field for field.
///
/// Its JSON always has the fields a strict server requires, which
/// [RunAgentInput]'s doesn't.
class const SimpleInputMapper() {
  /// Creates a mapper.
  this;

  /// Returns [input] as a [SimpleRunAgentInput].
  SimpleRunAgentInput call(RunAgentInput input) => SimpleRunAgentInput(
    threadId: input.threadId,
    runId: input.runId,
    parentRunId: input.parentRunId,
    state: input.state,
    messages: input.messages,
    tools: input.tools,
    context: input.context,
    forwardedProps: input.forwardedProps,
  );
}
