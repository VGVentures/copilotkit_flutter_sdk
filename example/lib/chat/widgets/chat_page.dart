import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/chat_view.dart';
import 'package:flutter/widgets.dart';

/// Chat with the runtime's `default` agent on the nearest `CopilotKit`
/// client.
class const ChatPage({super.key}) extends StatelessWidget {
  /// Id of the agent this page chats with.
  static const agentId = 'default';

  @override
  Widget build(BuildContext context) =>
      const CopilotChatProvider(agentId: agentId, child: ChatView());
}
