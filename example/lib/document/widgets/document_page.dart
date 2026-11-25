import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/document/widgets/document_view.dart';
import 'package:flutter/material.dart';

/// Opens the runtime's `document` agent on a new thread of [client] and
/// shows the [DocumentView] for it: state rendering, where the agent streams
/// a document into its shared state and the user edits it.
///
/// It takes the client, like the memories screen, so it works on a route
/// pushed above the `CopilotKit` of the chat.
class const DocumentPage({
  /// The client whose `document` agent writes the document.
  required final CopilotKitClient client,
  super.key,
}) extends StatelessWidget {
  /// Id of the agent on the runtime, see `tool/runtime/document_agent.ts`.
  static const agentId = 'document';

  @override
  Widget build(BuildContext context) => CopilotKit.value(
    client: client,
    child: const CopilotAgentScope(agentId: agentId, child: DocumentView()),
  );
}
