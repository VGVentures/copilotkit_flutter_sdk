import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Text input with a send button that turns into stop while the agent runs.
class const Composer({super.key}) extends StatefulWidget {
  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final bloc = context.read<CopilotChatBloc>();
    final text = _controller.text.trim();
    if (text.isEmpty || bloc.state.isRunning) return;
    bloc.add(ChatMessageSent(text));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = context.select<CopilotChatBloc, bool>(
      (bloc) => bloc.state.isRunning,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Ask anything',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (isRunning)
            IconButton.filled(
              tooltip: 'Stop',
              icon: const Icon(Icons.stop),
              onPressed: () => context.read<CopilotChatBloc>().add(
                const ChatStopRequested(),
              ),
            )
          else
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => IconButton.filled(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: value.text.trim().isEmpty ? null : _send,
              ),
            ),
        ],
      ),
    );
  }
}
