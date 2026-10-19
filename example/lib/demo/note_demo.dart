// PLACEHOLDER DEMO CONTENT.
//
// A stand-in component tool so rendering a UI component from the agent's
// arguments can be checked on device.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: lets the agent draw a [NoteCard] with the `showNote`
/// component around [child].
class const NoteDemo({required final Widget child, super.key})
    extends StatelessWidget {
  /// Keep in sync with [NoteCard].
  static final ObjectSchema parameters = Ack.object({
    'title': Ack.string().describe('Short title, e.g. "Pack a coat"'),
    'body': Ack.string().describe('One or two sentences'),
  });

  @override
  Widget build(BuildContext context) {
    return CopilotComponent(
      name: 'showNote',
      description: 'Shows a short note card, e.g. a tip or a summary.',
      parameters: parameters,
      builder: (context, args, status) => NoteCard(args: args, status: status),
      child: child,
    );
  }
}

/// Placeholder component for `showNote` calls: a card that fills in as the
/// arguments stream.
class const NoteCard({
  required final Map<String, Object?> args,
  required final ToolCallStatus status,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = args['title'];
    final body = args['body'];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title is String) Text(title, style: textTheme.titleMedium),
            if (body is String) Text(body),
            if (status == ToolCallStatus.inProgress) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
