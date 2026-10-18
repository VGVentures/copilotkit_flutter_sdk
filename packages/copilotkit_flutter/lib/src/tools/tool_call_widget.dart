import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Renders [call] with the nearest builder registered for its tool name,
/// falling back to the [ToolRenderer.nameFallback] builder, or nothing.
///
/// The builder is looked up above this widget, so the chat must be inside the
/// `CopilotTool` or `ToolRenderer` that provides it. In debug mode, a call
/// with no builder logs a hint once.
///
/// Keyed by the call id and kept alive inside lists, so builder state
/// survives status updates, rebuilds and scrolling.
class ToolCallWidget extends StatefulWidget {
  /// Creates a widget that renders [call].
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

  bool _warned = false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final builders = ToolRenderer.buildersOf(context);
    final builder =
        builders?[widget.call.name] ?? builders?[ToolRenderer.nameFallback];
    assert(() {
      if (builder == null && !_warned) {
        _warned = true;
        debugPrint(
          'No builder for the tool "${widget.call.name}": its call renders '
          'nothing. Put this ToolCallWidget inside the CopilotTool (or a '
          'ToolRenderer) for that tool.',
        );
      }
      return true;
    }(), 'unreachable');
    return builder?.call(context, widget.call) ?? const SizedBox.shrink();
  }
}
