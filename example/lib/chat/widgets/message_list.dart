import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Chat rows from [CopilotChatBloc]: text bubbles and inline tool calls.
///
/// Follows the bottom while text streams in, unless the user has scrolled
/// up; scrolling back to the bottom resumes following.
class const MessageList({super.key}) extends StatefulWidget {
  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  /// Distance from the end within which the list keeps following new
  /// content.
  static const _followThreshold = 48.0;

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
