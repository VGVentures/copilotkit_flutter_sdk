import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for a tool call.
typedef ToolCallWidgetBuilder = Widget Function(
  BuildContext context,
  ToolCallView call,
);

/// Registers how calls to the tool [name] render in its subtree.
///
/// Use [nameFallback] as [name] for a fallback that renders any tool without
/// its own builder. Nested renderers for the same name override outer ones.
/// Use it for tools the agent runs elsewhere (backend tools); `CopilotTool`
/// does the same for frontend tools.
class const ToolRenderer({
  /// Name of the tool, or [nameFallback] for the fallback.
  required final String name,

  /// Builds the widget for each call to [name].
  required final ToolCallWidgetBuilder builder,

  /// The subtree where [builder] applies.
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// Creates a renderer for calls to the tool [name].
  this;

  /// The [name] of a renderer that applies to any tool without its own
  /// builder.
  static const nameFallback = '*';

  /// The builders registered by the renderers above [context], by tool name,
  /// or `null` when there are none. Used by `ToolCallWidget`.
  @internal
  static Map<String, ToolCallWidgetBuilder>? buildersOf(BuildContext context) =>
      _ToolBuilders.maybeOf(context);

  @override
  Widget build(BuildContext context) {
    final parent = _ToolBuilders.maybeOf(context);
    return _ToolBuilders(builders: {...?parent, name: builder}, child: child);
  }
}

class const _ToolBuilders({
  required final Map<String, ToolCallWidgetBuilder> builders,
  required super.child,
}) extends InheritedWidget {
  static Map<String, ToolCallWidgetBuilder>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ToolBuilders>()?.builders;

  @override
  bool updateShouldNotify(_ToolBuilders oldWidget) =>
      builders.length != oldWidget.builders.length ||
      builders.entries.any(
        (e) => !identical(oldWidget.builders[e.key], e.value),
      );
}
