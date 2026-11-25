import 'dart:async';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/document/widgets/document_panel.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// The Document screen: the [DocumentPanel] and a field that asks the
/// `document` agent of the nearest `CopilotAgentScope` to write or change
/// it.
class const DocumentView({final Uuid _uuid = const Uuid(), super.key})
    extends StatefulWidget {
  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final agent = CopilotAgentScope.of(context);
    // The turn reports to the agent's state, which the panel reads.
    unawaited(
      CopilotKit.of(context).runAgent(
        agent.state.agentId,
        message: UserMessage(id: widget._uuid.v4(), content: text),
      ),
    );
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Document')),
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(child: DocumentPanel()),
            AgentStateBuilder<bool>(
              selector: (state) => state.isRunning,
              builder: (context, isRunning) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('document_prompt'),
                        controller: _controller,
                        enabled: !isRunning,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Ask the writer, e.g. "Write a haiku"',
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('document_send'),
                      tooltip: 'Send',
                      icon: const Icon(Icons.send),
                      onPressed: isRunning ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
