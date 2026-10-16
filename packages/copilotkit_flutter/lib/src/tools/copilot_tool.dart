import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/copilot_kit.dart';
import 'package:copilotkit_flutter/src/tools/tool_call_widget_builder.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// {@template copilot_tool}
/// Makes [tool] available to the agent while this widget is mounted.
///
/// Adds `ToolRegistered` to the nearest `CopilotKit` client and
/// `ToolUnregistered` on dispose. If [builder] is set, calls to the tool
/// render with it in [child] (see `ToolCallWidget`).
/// {@endtemplate}
class const CopilotTool({
  /// The tool to register.
  required final FrontendTool tool,

  /// The subtree where [builder] applies.
  required final Widget child,

  /// Builds the widget for each call to [tool], if set.
  final ToolCallWidgetBuilder? builder,
  super.key,
}) extends StatefulWidget {
  /// {@macro copilot_tool}
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
    _unregister();
    final client = _client!..add(ToolRegistered(widget.tool));
    _registered = (client, widget.tool);
  }

  void _unregister() {
    if (_registered case (final client, final tool)) {
      client.add(ToolUnregistered(tool));
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
