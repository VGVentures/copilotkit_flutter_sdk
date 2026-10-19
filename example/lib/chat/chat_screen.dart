import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/composer.dart';
import 'package:example/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Chat with the runtime's `default` agent.
///
/// Opens the agent with a `CopilotAgentScope` and builds the chat once the
/// nearest `CopilotKit` client holds it.
class const ChatPage({super.key}) extends StatelessWidget {
  /// Id of the agent this page chats with.
  static const agentId = 'default';

  @override
  Widget build(BuildContext context) {
    return CopilotAgentScope(
      agentId: agentId,
      child: Builder(
        builder: (context) => BlocProvider(
          create: (_) => CopilotChatBloc(
            client: CopilotKit.of(context),
            agent: context.read<CopilotAgentBloc>(),
          )..add(const ChatSubscriptionRequested()),
          child: const ChatView(),
        ),
      ),
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
