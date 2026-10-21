/// @docImport 'package:copilotkit_flutter/src/tools/widgets/copilot_tool.dart';
/// @docImport 'package:copilotkit_flutter/src/tools/widgets/tool_call_widget.dart';
library;

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_registration.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Answers a human-in-the-loop tool call with [result], which is sent to the
/// agent as the tool result: a `String` as it is, anything else JSON-encoded.
///
/// Only the first answer to a call counts.
typedef ToolCallResponder = void Function(Object? result);

/// Builds the widget for one [call] to a human-in-the-loop tool, with its
/// [args] decoded by the tool's [HumanInTheLoopTool.decode].
///
/// [args] is `null` while they can't be decoded yet, e.g. while they are
/// still streaming in. [respond] is `null` until the call waits for the user
/// ([ToolCallView.awaitingResponse]) and again once it has a result.
typedef HumanInTheLoopWidgetBuilder<T> = Widget Function(
  BuildContext context,
  ToolCallView call,
  T? args,
  ToolCallResponder? respond,
);

/// Makes the human-in-the-loop [tool] available to the agent while this
/// widget is mounted, and renders its calls with [builder].
///
/// Registers like [CopilotTool], on the nearest [CopilotKit] client. While
/// the agent's call waits for the user, [builder] gets a `respond` function;
/// calling it sends the answer and the agent continues. Unmounting this
/// widget while a call waits answers the call as cancelled.
///
/// The widget [builder] returns keeps its state while the call moves from
/// streaming to waiting to complete (see [ToolCallWidget]), so a card can
/// hold what the user typed or picked.
///
/// Keep [tool] stable across rebuilds, e.g. in a field: a different tool
/// replaces the registered one, an equal one changes nothing.
class const CopilotHumanInTheLoop<T>({
  /// The tool to register.
  required final HumanInTheLoopTool<T> tool,

  /// Builds the widget for each call to [tool].
  required final HumanInTheLoopWidgetBuilder<T> builder,

  /// The subtree where [builder] applies.
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// Creates a widget that registers [tool] while mounted.
  this;

  @override
  Widget build(BuildContext context) {
    return ToolRegistration(
      tool: tool,
      child: ToolRenderer(
        name: tool.name,
        builder: (context, call) {
          final client = CopilotKit.of(context);
          return builder(
            context,
            call,
            tool.tryDecode(call.args),
            call.awaitingResponse
                ? (result) => client.respondToToolCall(call.id, result)
                : null,
          );
        },
        child: child,
      ),
    );
  }
}
