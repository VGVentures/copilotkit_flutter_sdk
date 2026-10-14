import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Distance from the end within which the list keeps following new content.
const _followThreshold = 48.0;

/// Chat rows from [CopilotChatBloc]: text bubbles and inline tool calls.
///
/// Follows the bottom while text streams in, unless the user has scrolled
/// up; scrolling back to the bottom resumes following.
class MessageList extends StatefulWidget {
  const new({super.key});

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _controller = ScrollController();
  var _followBottom = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    _followBottom = notification.metrics.extentAfter < _followThreshold;
    return false;
  }

  void _scrollToBottom() {
    if (!_followBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CopilotChatBloc, CopilotChatState>(
      listenWhen: (previous, current) => previous.rows != current.rows,
      listener: (context, state) => _scrollToBottom(),
      builder: (context, state) {
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.all(16),
            itemCount: state.rows.length,
            itemBuilder: (context, index) => switch (state.rows[index]) {
              ChatMessageRow(:final message) => MessageBubble(
                key: ValueKey(message.id),
                message: message,
              ),
              ChatToolCallRow(:final call) => ToolCallWidget(call: call),
            },
          ),
        );
      },
    );
  }
}

/// A user (right) or assistant (left) text bubble.
///
/// Assistant text is rendered as markdown; the renderer tolerates the
/// unfinished markdown of a reply that is still streaming.
class MessageBubble extends StatelessWidget {
  const new({required this.message, super.key});

  final Message message;

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
