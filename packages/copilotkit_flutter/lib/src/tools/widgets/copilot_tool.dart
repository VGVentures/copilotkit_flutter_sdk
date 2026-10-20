import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Makes [tool] available to the agent while this widget is mounted.
///
/// Registers it on the nearest `CopilotKit` client and unregisters it on
/// dispose. If [builder] is set, calls to the tool
/// render with it in [child] (see `ToolCallWidget`).
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

  /// The tool instance registered and the client it was registered on, so
  /// only that registration is undone.
  (CopilotKitClient, FrontendTool)? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (client != _client) {
      _client = client;
      _register();
    }
  }

  @override
  void didUpdateWidget(CopilotTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tool != oldWidget.tool) _register();
  }

  void _register() {
    _unregister();
    final client = _client!..registerTool(widget.tool);
    _registered = (client, widget.tool);
  }

  void _unregister() {
    if (_registered case (final client, final tool)) {
      client.unregisterTool(tool);
    }
    _registered = null;
  }

  @override
  void dispose() {
    _unregister();
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
