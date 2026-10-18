import 'dart:convert';

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
/// render with it in `ToolCallWidget`s inside [child]. The tool itself is
/// available app-wide, so a chat outside of [child] (a bottom sheet, another
/// route) runs the tool but doesn't render its calls with [builder]: put the
/// chat inside [child], or add a `ToolRenderer` above it.
///
/// Rebuilding with a new `FrontendTool` doesn't re-register the tool as long
/// as its name, description and parameters stay the same; calls always run the
/// handler of the latest widget. So `tool` can be created inline in `build`.
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

  /// The tool registered and the client it was registered on, so only that
  /// registration is undone. The tool is a stand-in for `widget.tool` that
  /// stays the same while the tool's configuration does, and calls the
  /// handler of the current widget.
  (CopilotKitClient, FrontendTool)? _registered;

  /// What [_registered] was built from, to tell when a rebuild changed it.
  String? _fingerprint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
      _client = client;
      _registerTool();
    }
  }

  @override
  void didUpdateWidget(CopilotTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_fingerprintOf(widget.tool) != _fingerprint) _registerTool();
  }

  static String _fingerprintOf(FrontendTool tool) =>
      jsonEncode([tool.name, tool.description, tool.parameters.toJsonSchema()]);

  void _registerTool() {
    _unregisterTool();
    final tool = FrontendTool(
      name: widget.tool.name,
      description: widget.tool.description,
      parameters: widget.tool.parameters,
      handler: (args, {required signal}) =>
          widget.tool.handler(args, signal: signal),
    );
    final client = _client!..add(ToolRegistered(tool));
    _registered = (client, tool);
    _fingerprint = _fingerprintOf(widget.tool);
  }

  void _unregisterTool() {
    if (_registered case (final client, final tool)) {
      client.add(ToolUnregistered(tool));
    }
    _registered = null;
  }

  @override
  void dispose() {
    _unregisterTool();
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
