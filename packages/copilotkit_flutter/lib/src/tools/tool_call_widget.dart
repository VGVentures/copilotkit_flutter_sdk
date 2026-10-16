import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
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
    final builders = ToolRenderer.buildersOf(context);
    final builder =
        builders?[widget.call.name] ?? builders?[ToolRenderer.nameFallback];
    return builder?.call(context, widget.call) ?? const SizedBox.shrink();
  }
}
