import 'package:copilotkit/src/tools/models/tool_call_status.dart';
import 'package:copilotkit/src/tools/models/tool_call_view.dart';

/// The status changes of a [ToolCallView] over its lifecycle.
///
/// Each returns an equal view when the change doesn't apply.
extension ToolCallViewTransitions on ToolCallView {
  /// Returns this view marked executing if its arguments were still
  /// streaming in.
  ToolCallView finishArgs() => status == ToolCallStatus.inProgress
      ? copyWith(status: ToolCallStatus.executing)
      : this;

  /// Returns this view marked as waiting for the user's answer, if it's
  /// executing.
  ToolCallView awaitResponse() => status == ToolCallStatus.executing
      ? copyWith(awaitingResponse: true)
      : this;

  /// Returns this view marked complete with [result], and no longer awaiting
  /// a response.
  ToolCallView complete(String result) => copyWith(
    status: ToolCallStatus.complete,
    result: () => result,
    awaitingResponse: false,
  );
}
