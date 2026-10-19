import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/copilot_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the agent [agentId] on the nearest `CopilotKit` client and provides
/// it to [child] and everything below it.
///
/// Read the agent below with `context.read<CopilotAgentBloc>()`, or watch
/// parts of its state with `AgentStateBuilder` or
/// `BlocSelector<CopilotAgentBloc, CopilotAgentState, T>`. A tool card can
/// reach the agent this way, and a form can edit the shared state by adding
/// `AgentStateSet` to it.
///
/// The client owns the agent, so the scope never closes it: the agent lives
/// until the client closes. Two scopes with the same [agentId] under the same
/// client share one agent. [child] is built once the client has opened the
/// agent, which takes one event-loop turn after this widget mounts.
class const CopilotAgentScope({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,

  /// The subtree that can read the agent.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a scope for the agent [agentId].
  this;

  @override
  State<CopilotAgentScope> createState() => _CopilotAgentScopeState();
}

class _CopilotAgentScopeState extends State<CopilotAgentScope> {
  CopilotKitBloc? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
      _client = client..add(AgentOpened(widget.agentId));
    }
  }

  @override
  void didUpdateWidget(CopilotAgentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.agentId != oldWidget.agentId) {
      _client!.add(AgentOpened(widget.agentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentId = widget.agentId;
    return BlocSelector<CopilotKitBloc, CopilotKitState, CopilotAgentBloc?>(
      bloc: _client,
      selector: (state) => state.agents[agentId],
      builder: (context, agent) {
        if (agent == null) return const SizedBox.shrink();
        return BlocProvider<CopilotAgentBloc>.value(
          value: agent,
          child: widget.child,
        );
      },
    );
  }
}
