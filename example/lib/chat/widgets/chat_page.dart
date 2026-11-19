import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/chat_view.dart';
import 'package:flutter/widgets.dart';

/// Chat with the runtime's `default` agent on the nearest `CopilotKit`
/// client.
class const ChatPage({
  /// Shown between the app bar and the messages, e.g. a panel of the app's
  /// own state. `null` for none.
  final Widget? header,

  /// Called with the id of the thread the user switches to, e.g. to keep it
  /// for the next launch. `null` for none.
  final ValueChanged<String>? onThreadSelected,
  super.key,
}) extends StatelessWidget {
  /// Id of the agent this page chats with.
  static const agentId = 'default';

  @override
  Widget build(BuildContext context) => CopilotChatProvider(
    agentId: agentId,
    child: ChatView(header: header, onThreadSelected: onThreadSelected),
  );
}
