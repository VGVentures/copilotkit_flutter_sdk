import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/composer.dart';
import 'package:example/chat/widgets/message_list.dart';
import 'package:example/threads/threads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The chat screen: an optional header and the messages above a composer,
/// with an error banner when the last run failed.
class const ChatView({
  /// Shown between the app bar and the messages. `null` for none.
  final Widget? header,

  /// Called with the id of the thread the user switches to. `null` for none.
  final ValueChanged<String>? onThreadSelected,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hasError = context.select<CopilotChatBloc, bool>(
      (bloc) => bloc.state.error != null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('CopilotKit'),
        actions: [
          IconButton(
            key: const Key('open_threads'),
            tooltip: 'Conversations',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => _openThreads(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ?header,
            const Expanded(child: MessageList()),
            if (hasError)
              Padding(
                key: const Key('chat_error'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Something went wrong. Try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Composer(),
          ],
        ),
      ),
    );
  }

  Future<void> _openThreads(BuildContext context) async {
    final client = CopilotKit.of(context);
    final agentId = client.agents.keys.first;
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ThreadsPage(
          client: client,
          agentId: agentId,
          currentThreadId: client.agent(agentId).state.threadId,
        ),
      ),
    );
    if (selected == null) return;
    await client.switchAgentThread(agentId, selected);
    onThreadSelected?.call(selected);
  }
}
