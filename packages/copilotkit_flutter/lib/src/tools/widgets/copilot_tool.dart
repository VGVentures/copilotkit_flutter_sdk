import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_registration.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for one [call] to a tool, with its [args] decoded by
/// the tool's `FrontendTool.decode`.
///
/// [args] is `null` while they can't be decoded yet, e.g. while they are
/// still streaming in.
typedef CopilotToolBuilder<T> = Widget Function(
  BuildContext context,
  ToolCallView call,
  T? args,
);

/// Makes [tool] available to the agent while this widget is mounted.
///
/// Registers it on the nearest `CopilotKit` client and unregisters it on
/// dispose. If [builder] is set, calls to the tool render with it in [child]
/// (see `ToolCallWidget`).
class const CopilotTool<T>({
  /// The tool to register.
  required final FrontendTool<T> tool,

  /// The subtree where [builder] applies.
  required final Widget child,

  /// Builds the widget for each call to [tool], if set.
  final CopilotToolBuilder<T>? builder,
  super.key,
}) extends StatelessWidget {
  /// Creates a widget that registers [tool] while mounted.
  this;

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    return ToolRegistration(
      tool: tool,
      child: builder == null
          ? child
          : ToolRenderer(
              name: tool.name,
              builder: (context, call) =>
                  builder(context, call, call.args.tryDecode(tool.decode)),
              child: child,
            ),
    );
  }
}
