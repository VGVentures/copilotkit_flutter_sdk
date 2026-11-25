import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/agent/agent.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:copilotkit_flutter/src/tools/tools.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Marks [child] as the control [name], so a tap on it is recorded as a
/// `click` trajectory event while the nearest `CopilotKit` captures one:
/// the Flutter version of the web's `data-copilotkit-action`.
///
/// It listens to the raw pointer, so [child] handles the tap as usual. The
/// event is `{target: {tag: 'CopilotAction', action: name, input:
/// 'pointer'}, route}`. Inside a [ToolCallWidget] it also has the call's
/// `toolCallId`, `toolName` and `toolStatus`, and below a
/// [CopilotAgentScope] the agent's `agentId` and `threadId`, so Learning
/// can tie the tap to the tool card it was on.
class const CopilotAction({
  /// The name of the action, e.g. `approve`.
  required final String name,

  /// The control the user taps.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget that records taps on [child] as the action [name].
  this;

  @override
  State<CopilotAction> createState() => _CopilotActionState();
}

class _CopilotActionState extends State<CopilotAction> {
  Offset? _down;

  void _onUp(PointerUpEvent event) {
    final down = _down;
    _down = null;
    // A drag or a scroll is not a tap.
    if (down == null || (event.position - down).distance > kTouchSlop) return;
    final client = CopilotKit.maybeRead(context);
    if (client == null) return;
    final call = ToolCallWidget.maybeCallOf(context);
    final agent = CopilotAgentScope.maybeOf(context)?.state;
    client.recordTrajectoryEvent(TrajectoryBuiltInEvent.click, {
      'target': {
        'tag': 'CopilotAction',
        'action': widget.name,
        'input': 'pointer',
      },
      'route': ModalRoute.of(context)?.settings.name,
      if (agent != null) ...{
        'agentId': agent.agentId,
        'threadId': agent.threadId,
      },
      if (call != null) ...{
        'toolCallId': call.id,
        'toolName': call.name,
        'toolStatus': call.status.name,
      },
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => _down = event.position,
    onPointerUp: _onUp,
    onPointerCancel: (_) => _down = null,
    child: widget.child,
  );
}
