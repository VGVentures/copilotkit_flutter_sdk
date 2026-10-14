import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/composer.dart';
import 'package:example/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Chat with the runtime's `default` agent.
class const ChatPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final client = CopilotKit.of(context);
    return BlocProvider(
      create: (_) => CopilotChatBloc(agent: client.agent('default')),
      child: const ChatView(),
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
