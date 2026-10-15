import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/copilot_kit.dart';
import 'package:copilotkit_flutter/src/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Makes [tool] available to the agent while this widget is mounted.
///
/// Registers [tool] on the nearest `CopilotKit` client and unregisters it on
/// dispose. If [builder] is set, calls to the tool render with it in
/// [child] (see `ToolCallWidget`).
class const CopilotTool({
  /// The tool to register.
  required final FrontendTool tool,

  /// The subtree where [builder] applies.
  required final Widget child,

  /// Builds the widget for each call to [tool], if set.
  final ToolCallWidgetBuilder? builder,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget that registers [tool] while mounted.
  this;

  @override
  State<CopilotTool> createState() => _CopilotToolState();
}

class _CopilotToolState extends State<CopilotTool> {
  CopilotKitClient? _client;
  void Function()? _unregister;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
      _client = client;
      _register();
    }
  }

  @override
  void didUpdateWidget(CopilotTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.tool, oldWidget.tool)) _register();
  }

  void _register() {
    _unregister?.call();
    _unregister = _client!.registerTool(widget.tool);
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder == null) return widget.child;
    return ToolRenderer(
      name: widget.tool.name,
      builder: builder,
      child: widget.child,
    );
  }
}
