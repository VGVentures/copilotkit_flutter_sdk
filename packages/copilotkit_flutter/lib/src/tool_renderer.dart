import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for a tool call.
typedef ToolCallWidgetBuilder = Widget Function(
  BuildContext context,
  ToolCallView call,
);

/// {@template tool_renderer}
/// Registers how calls to the tool [name] render in its subtree.
///
/// Use `'*'` as [name] for a fallback that renders any tool without its own
/// builder. Nested renderers for the same name override outer ones. Use it
/// for tools the agent runs elsewhere (backend tools); `CopilotTool` does the
/// same for frontend tools.
/// {@endtemplate}
class ToolRenderer extends StatelessWidget {
  /// {@macro tool_renderer}
  const new({
    required this.name,
    required this.builder,
    required this.child,
    super.key,
  });

  /// Name of the tool, or `'*'` for the fallback.
  final String name;

  /// Builds the widget for each call to [name].
  final ToolCallWidgetBuilder builder;

  /// The subtree where [builder] applies.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = _ToolBuilders.maybeOf(context);
    return _ToolBuilders(builders: {...?parent, name: builder}, child: child);
  }
}

/// {@template tool_call_widget}
/// Renders [call] with the nearest builder registered for its tool name,
/// falling back to the `'*'` builder, or nothing.
///
/// Keyed by the call id and kept alive inside lists, so builder state
/// survives status updates, rebuilds and scrolling.
/// {@endtemplate}
class ToolCallWidget extends StatefulWidget {
  /// {@macro tool_call_widget}
  new({required this.call}) : super(key: ValueKey(call.id));

  /// The call to render.
  final ToolCallView call;

  @override
  State<ToolCallWidget> createState() => _ToolCallWidgetState();
}

class _ToolCallWidgetState extends State<ToolCallWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final builders = _ToolBuilders.maybeOf(context);
    final builder = builders?[widget.call.name] ?? builders?['*'];
    return builder?.call(context, widget.call) ?? const SizedBox.shrink();
  }
}

class _ToolBuilders extends InheritedWidget {
  const new({required this.builders, required super.child});

  final Map<String, ToolCallWidgetBuilder> builders;

  static Map<String, ToolCallWidgetBuilder>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ToolBuilders>()?.builders;

  @override
  bool updateShouldNotify(_ToolBuilders oldWidget) =>
      builders.length != oldWidget.builders.length ||
      builders.entries.any(
        (e) => !identical(oldWidget.builders[e.key], e.value),
      );
}
