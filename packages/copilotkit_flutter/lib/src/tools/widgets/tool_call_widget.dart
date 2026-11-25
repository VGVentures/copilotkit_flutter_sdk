import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Renders [call] with the nearest builder registered for its tool name,
/// falling back to the [ToolRenderer.nameFallback] builder, or nothing.
///
/// Keyed by the call id and kept alive inside lists, so builder state
/// survives status updates, rebuilds and scrolling.
class ToolCallWidget extends StatefulWidget {
  /// Creates a widget that renders [call].
  new({required this.call}) : super(key: ValueKey(call.id));

  /// The call to render.
  final ToolCallView call;

  /// Returns the call rendered by the nearest [ToolCallWidget] ancestor, or
  /// `null` outside one, e.g. for a widget that reports which call it is
  /// part of. Doesn't rebuild [context] when the call changes.
  static ToolCallView? maybeCallOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ToolCallScope>()?.call;

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
    final builders = ToolRenderer.maybeOf(context);
    final builder =
        builders?[widget.call.name] ?? builders?[ToolRenderer.nameFallback];
    return _ToolCallScope(
      call: widget.call,
      child: Builder(
        builder: (context) =>
            builder?.call(context, widget.call) ?? const SizedBox.shrink(),
      ),
    );
  }
}

class const _ToolCallScope({
  required final ToolCallView call,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_ToolCallScope oldWidget) => call != oldWidget.call;
}
