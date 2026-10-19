import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// A user (right) or assistant (left) text bubble.
///
/// Assistant text is rendered as markdown; the renderer tolerates the
/// unfinished markdown of a reply that is still streaming.
class const MessageBubble({required final Message message, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message is UserMessage;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? colors.primary : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: isUser
              ? Text(
                  message.content ?? '',
                  style: TextStyle(color: colors.onPrimary),
                )
              : GptMarkdown(
                  message.content ?? '',
                  style: TextStyle(color: colors.onSurface),
                ),
        ),
      ),
    );
  }
}
