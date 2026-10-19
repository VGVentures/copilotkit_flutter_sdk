import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/tool_registration.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Makes [tool] available to the agent while this widget is mounted.
///
/// Adds `ToolRegistered` to the nearest `CopilotKit` client and
/// `ToolUnregistered` on dispose. If [builder] is set, calls to the tool
/// render with it in [child] (see `ToolCallWidget`).
class const CopilotTool({
  /// The tool to register.
  required final FrontendTool tool,

  /// The subtree where [builder] applies.
  required final Widget child,

  /// Builds the widget for each call to [tool], if set.
  final ToolCallWidgetBuilder? builder,
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
          : ToolRenderer(name: tool.name, builder: builder, child: child),
    );
  }
}
