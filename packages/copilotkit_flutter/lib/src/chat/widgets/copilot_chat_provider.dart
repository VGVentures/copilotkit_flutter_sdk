import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/chat/bloc/copilot_chat_bloc.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Provides a [CopilotChatBloc] for the agent [agentId] of the nearest
/// [CopilotKit] client to [child].
///
/// The bloc is subscribed to the agent and closed with this widget. When the
/// client or [agentId] changes, a new bloc replaces it and the old one is
/// closed; [child] keeps its state.
class const CopilotChatProvider({
  /// Id of the agent to chat with, e.g. `default`.
  required final String agentId,

  /// The subtree that reads the bloc, e.g. with `context.read`.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a provider of the chat with the agent [agentId].
  this;

  @override
  State<CopilotChatProvider> createState() => _CopilotChatProviderState();
}

class _CopilotChatProviderState extends State<CopilotChatProvider> {
  /// The bloc provided and the client and agent id it was created for.
  (CopilotKitClient, String, CopilotChatBloc)? _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CopilotChatProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Creates a bloc when the client or agent id differs from the ones the
  /// current bloc was created for, and closes the current one.
  ///
  /// Both callbacks read the latest client, so a client and an agent id
  /// that change together create one bloc, on the new client.
  void _sync() {
    final client = CopilotKit.of(context);
    final agentId = widget.agentId;
    final previous = _current;
    if (previous case (final currentClient, final currentAgentId, _)
        when currentClient == client && currentAgentId == agentId) {
      return;
    }
    _current = (
      client,
      agentId,
      CopilotChatBloc(client: client, agentId: agentId)
        ..add(const ChatSubscriptionRequested()),
    );
    if (previous case (_, _, final bloc)) unawaited(bloc.close());
  }

  @override
  void dispose() {
    if (_current case (_, _, final bloc)) unawaited(bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: _current!.$3, child: widget.child);
  }
}
