import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/copilot_kit.dart';
import 'package:copilotkit_flutter/src/tools/tool_registration.dart';
import 'package:copilotkit_flutter/src/tools/tool_renderer.dart';
import 'package:flutter/widgets.dart';

/// Answers a human-in-the-loop tool call with [result], which is sent to the
/// agent as the tool result: a `String` as it is, anything else JSON-encoded.
///
/// Only the first answer to a call counts.
typedef ToolCallResponder = void Function(Object? result);

/// Builds the widget for a call to a human-in-the-loop tool.
///
/// [respond] is `null` until the call waits for the user
/// (`ToolCallView.awaitingResponse`) and again once it has a result.
typedef HumanInTheLoopWidgetBuilder = Widget Function(
  BuildContext context,
  ToolCallView call,
  ToolCallResponder? respond,
);

/// Makes the human-in-the-loop [tool] available to the agent while this
/// widget is mounted, and renders its calls with [builder].
///
/// Registers like `CopilotTool`, on the nearest `CopilotKit` client. While
/// the agent's call waits for the user, [builder] gets a `respond` function;
/// calling it sends the answer and the agent continues. Unmounting this
/// widget while a call waits answers the call as cancelled.
///
/// The widget [builder] returns keeps its state while the call moves from
/// streaming to waiting to complete (see `ToolCallWidget`), so a card can
/// hold what the user typed or picked.
///
/// Keep [tool] stable across rebuilds, e.g. in a field: a different tool
/// replaces the registered one, an equal one changes nothing.
class const CopilotHumanInTheLoop({
  /// The tool to register.
  required final HumanInTheLoopTool tool,

  /// Builds the widget for each call to [tool].
  required final HumanInTheLoopWidgetBuilder builder,

  /// The subtree where [builder] applies.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget that registers [tool] while mounted.
  this;

  @override
  State<CopilotHumanInTheLoop> createState() => _CopilotHumanInTheLoopState();
}

class _CopilotHumanInTheLoopState extends State<CopilotHumanInTheLoop> {
  /// The builder `ToolRenderer` gets: stable between rebuilds unless
  /// `widget.builder` changes, so renderers below only rebuild then.
  late ToolCallWidgetBuilder _render = _wrap(widget.builder);

  @override
  void didUpdateWidget(CopilotHumanInTheLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.builder, oldWidget.builder)) {
      _render = _wrap(widget.builder);
    }
  }

  /// Adapts [builder] to a `ToolCallWidgetBuilder`, adding `respond` while
  /// the call waits for the user.
  static ToolCallWidgetBuilder _wrap(HumanInTheLoopWidgetBuilder builder) {
    return (context, call) {
      final client = CopilotKit.of(context);
      return builder(
        context,
        call,
        call.awaitingResponse
            ? (result) => client.add(ToolCallResponded(call.id, result))
            : null,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return ToolRegistration(
      tool: widget.tool,
      child: ToolRenderer(
        name: widget.tool.name,
        builder: _render,
        child: widget.child,
      ),
    );
  }
}
