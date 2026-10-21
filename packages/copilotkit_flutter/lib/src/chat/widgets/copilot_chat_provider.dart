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
  CopilotKitClient? _client;
  CopilotChatBloc? _bloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (client != _client) {
      _client = client;
      _create();
    }
  }

  @override
  void didUpdateWidget(CopilotChatProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.agentId != oldWidget.agentId) _create();
  }

  void _create() {
    final previous = _bloc;
    _bloc = CopilotChatBloc(client: _client!, agentId: widget.agentId)
      ..add(const ChatSubscriptionRequested());
    unawaited(previous?.close());
  }

  @override
  void dispose() {
    unawaited(_bloc?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: _bloc!, child: widget.child);
  }
}
