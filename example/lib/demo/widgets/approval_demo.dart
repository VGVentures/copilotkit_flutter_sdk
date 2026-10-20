// Placeholder demo content: a stand-in human-in-the-loop tool so the
// approval flow (the agent asks, the user decides, the agent continues) can
// be checked on a device.
import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/approval_args.dart';
import 'package:example/demo/widgets/approval_card.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: registers the `confirmAction` human-in-the-loop tool and
/// renders its calls as an [ApprovalCard] around [child].
class const ApprovalDemo({required final Widget child, super.key})
    extends StatelessWidget {
  /// The tool the agent calls before it does something irreversible.
  static final HumanInTheLoopTool<ApprovalArgs> tool = HumanInTheLoopTool(
    name: 'confirmAction',
    description:
        'Ask the user to confirm an action before doing it. Call it before '
        'anything irreversible and wait for the answer.',
    // Keep in sync with ApprovalArgs.
    parameters: Ack.object({
      'action': Ack.string().describe(
        'What will happen, e.g. "Delete 3 files"',
      ),
    }),
    decode: ApprovalArgs.fromJson,
  );

  @override
  Widget build(BuildContext context) {
    return CopilotHumanInTheLoop(
      tool: tool,
      builder: (context, call, args, respond) =>
          ApprovalCard(call: call, args: args, respond: respond),
      child: child,
    );
  }
}
