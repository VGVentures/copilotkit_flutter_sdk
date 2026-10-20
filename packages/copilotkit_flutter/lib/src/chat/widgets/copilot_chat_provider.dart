import 'package:copilotkit_flutter/src/chat/bloc/copilot_chat_bloc.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Provides a [CopilotChatBloc] for the agent [agentId] of the nearest
/// `CopilotKit` client to [child].
///
/// The bloc is subscribed to the agent and closed with this widget. A new
/// bloc is created when the client or [agentId] changes.
class const CopilotChatProvider({
  /// Id of the agent to chat with, e.g. `default`.
  required final String agentId,

  /// The subtree that reads the bloc, e.g. with `context.read`.
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// Creates a provider of the chat with the agent [agentId].
  this;

  @override
  Widget build(BuildContext context) {
    final client = CopilotKit.of(context);
    return BlocProvider(
      key: ValueKey((client, agentId)),
      create: (_) =>
          CopilotChatBloc(client: client, agentId: agentId)
            ..add(const ChatSubscriptionRequested()),
      child: child,
    );
  }
}
