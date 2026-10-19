import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/composer.dart';
import 'package:example/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Chat with the runtime's `default` agent.
///
/// Opens the agent on the nearest `CopilotKit` client and builds the chat
/// once the client's state holds it.
class const ChatPage({super.key}) extends StatefulWidget {
  /// Id of the agent this page chats with.
  static const agentId = 'default';

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  CopilotKitClient? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
      _client = client..add(const AgentOpened(ChatPage.agentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<CopilotKitClient, CopilotKitState, CopilotAgent?>(
      bloc: _client,
      selector: (state) => state.agents[ChatPage.agentId],
      builder: (context, agent) {
        if (agent == null) return const SizedBox.shrink();
        return BlocProvider(
          create: (_) =>
              CopilotChatBloc(agent: agent)
                ..add(const ChatSubscriptionRequested()),
          child: const ChatView(),
        );
      },
    );
  }
}

class const ChatView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hasError = context.select<CopilotChatBloc, bool>(
      (bloc) => bloc.state.error != null,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('CopilotKit')),
      body: SafeArea(
        child: Column(
          children: [
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
}
