import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/approval_args.dart';
import 'package:flutter/material.dart';

/// Placeholder generative UI for `confirmAction` calls.
///
/// Shows **Approve** and **Reject** while the call waits for the user
/// ([respond] is set), and the decision once the call is complete.
class const ApprovalCard({
  /// The call to show.
  required final ToolCallView call,

  /// Answers the call, or `null` unless it waits for the user.
  required final ToolCallResponder? respond,

  /// The arguments of [call], or `null` while they can't be decoded yet.
  final ApprovalArgs? args,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final respond = this.respond;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(args?.action ?? 'Waiting for the details…'),
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
