import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/tool_registration.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Builds the component for a call to a `CopilotComponent`.
///
/// [args] are the arguments of the call, partial while [status] is
/// `ToolCallStatus.inProgress`.
typedef ComponentWidgetBuilder = Widget Function(
  BuildContext context,
  Map<String, Object?> args,
  ToolCallStatus status,
);

/// Lets the agent draw the component [builder] builds in the chat, while this
/// widget is mounted.
///
/// The Flutter counterpart of React's `useComponent`. It registers a
/// `ComponentTool` named [name] on the nearest `CopilotKit` client, with
/// [parameters] as the arguments the agent sends, and renders each call with
/// [builder] in [child] (see `ToolCallWidget`). The agent is told that the
/// tool "renders a visual UI component for the user", followed by
/// [description].
///
/// There is no handler: nothing runs in the app and nothing waits for the
/// user, so the agent doesn't run again after the call. The client answers the
/// call with a short note so the conversation stays valid; see
/// `ComponentTool`. For a component the user answers, use
/// `CopilotHumanInTheLoop`.
class const CopilotComponent({
  /// Name of the component and of the tool the agent calls it by.
  required final String name,

  /// Schema of the arguments the agent sends, built with `Ack.object`.
  required final ObjectSchema parameters,

  /// Builds the component for each call.
  required final ComponentWidgetBuilder builder,

  /// The subtree where [builder] applies.
  required final Widget child,

  /// What the component shows and when to use it, for the agent.
  final String? description,

  /// Id of the only agent that gets the tool, or `null` for every agent.
  final String? agentId,
  super.key,
}) extends StatelessWidget {
  /// Creates a widget that registers the component [name] while mounted.
  this;

  @override
  Widget build(BuildContext context) {
    return ToolRegistration(
      tool: ComponentTool(
        name: name,
        parameters: parameters,
        description: description,
        agentId: agentId,
      ),
      child: ToolRenderer(
        name: name,
        builder: (context, call) => builder(context, call.args, call.status),
        child: child,
      ),
    );
  }
}
