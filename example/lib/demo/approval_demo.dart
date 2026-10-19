// PLACEHOLDER DEMO CONTENT.
//
// A stand-in human-in-the-loop tool so the approval flow (the agent asks, the
// user decides, the agent continues) can be checked on device.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: registers the `confirmAction` human-in-the-loop tool and
/// renders its calls as an [ApprovalCard] around [child].
class const ApprovalDemo({required final Widget child, super.key})
    extends StatelessWidget {
  /// The tool the agent calls before it does something irreversible.
  static final tool = HumanInTheLoopTool(
    name: 'confirmAction',
    description:
        'Ask the user to confirm an action before doing it. Call it before '
        'anything irreversible and wait for the answer.',
    parameters: Ack.object({
      'action': Ack.string().describe(
        'What will happen, e.g. "Delete 3 files"',
      ),
    }),
  );

  @override
  Widget build(BuildContext context) {
    return CopilotHumanInTheLoop(
      tool: tool,
      builder: (context, call, respond) =>
          ApprovalCard(call: call, respond: respond),
      child: child,
    );
  }
}

/// Placeholder generative UI for `confirmAction` calls.
///
/// Shows **Approve** and **Reject** while the call waits for the user
/// (`respond` is set), and the decision once the call is complete.
class const ApprovalCard({
  required final ToolCallView call,
  required final ToolCallResponder? respond,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final action = call.args['action'];
    final respond = this.respond;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action is String ? action : 'Waiting for the details…'),
            const SizedBox(height: 8),
            if (respond != null)
              Row(
                children: [
                  FilledButton(
                    onPressed: () => respond({'decision': 'approve'}),
                    child: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => respond({'decision': 'reject'}),
                    child: const Text('Reject'),
                  ),
                ],
              )
            else if (call.status == ToolCallStatus.complete)
              Text('Answer: ${call.result}'),
          ],
        ),
      ),
    );
  }
}
