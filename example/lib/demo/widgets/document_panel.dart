// Placeholder demo content: a document kept in the agent's shared state, so
// state rendering while the agent writes (and the user's edits reaching it)
// can be checked on a device.
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/streamed_document.dart';
import 'package:flutter/material.dart';

/// Placeholder demo: shows the `document` of the agent's shared state as the
/// agent streams it, and lets the user edit it between runs.
///
/// Reads the agent of the nearest `CopilotAgentScope`. While the agent runs,
/// a **LIVE** badge shows and the text is read-only. Edits go through
/// `CopilotAgent.setSharedState`, so the next run sends them.
class const DocumentPanel({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AgentStateBuilder<(StreamedDocument, bool)>(
      selector: (state) =>
          (StreamedDocument.fromShared(state.sharedState), state.isRunning),
      builder: (context, value) {
        final (document, isRunning) = value;
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Shared document',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    if (isRunning) const _LiveBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                _DocumentField(
                  text: document.text,
                  readOnly: isRunning,
                  onChanged: (text) {
                    final agent = CopilotAgentScope.of(context);
                    agent.setSharedState(
                      StreamedDocument(text: text)
                          .toShared(agent.state.sharedState),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class const _LiveBadge() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          'LIVE',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.onErrorContainer),
        ),
      ),
    );
  }
}

class const _DocumentField({
  required final String text,
  required final bool readOnly,
  required final ValueChanged<String> onChanged,
}) extends StatefulWidget {
  @override
  State<_DocumentField> createState() => _DocumentFieldState();
}

class _DocumentFieldState extends State<_DocumentField> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(_DocumentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The agent's tokens arrive as new text; the user's own edits are
    // already in the controller.
    if (widget.text != _controller.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: widget.readOnly,
      minLines: 3,
      maxLines: 6,
      onChanged: widget.onChanged,
      decoration: const InputDecoration(
        hintText: 'No document yet. Ask the agent to write one.',
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
