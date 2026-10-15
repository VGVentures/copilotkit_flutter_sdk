import 'package:copilotkit_flutter/src/tools/tool_call_widget_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// {@template tool_renderer}
/// Registers how calls to the tool [name] render in its subtree.
///
/// Use `'*'` as [name] for a fallback that renders any tool without its own
/// builder. Nested renderers for the same name override outer ones. Use it
/// for tools the agent runs elsewhere (backend tools); `CopilotTool` does the
/// same for frontend tools.
/// {@endtemplate}
class const ToolRenderer({
  /// Name of the tool, or `'*'` for the fallback.
  required final String name,

  /// Builds the widget for each call to [name].
  required final ToolCallWidgetBuilder builder,

  /// The subtree where [builder] applies.
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// {@macro tool_renderer}
  this;

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
