import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/widgets.dart';

/// Opens the agent [agentId] on the nearest `CopilotKit` client and provides
/// it to [child] and everything below it.
///
/// Read the agent below with [CopilotAgentScope.of], or watch parts of its
/// state with `AgentStateBuilder`. A tool card can reach the agent this way,
/// and a form can edit the shared state with `CopilotAgent.setSharedState`.
///
/// The client owns the agent, so the scope never closes it: the agent lives
/// until the client closes. Two scopes with the same [agentId] under the same
/// client share one agent.
class const CopilotAgentScope({
  /// Id of the agent on the runtime, e.g. `default`.
  required final String agentId,

  /// The subtree that can read the agent.
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  /// Creates a scope for the agent [agentId].
  this;

  /// Returns the agent of the nearest [CopilotAgentScope] ancestor.
  ///
  /// Throws a [FlutterError] if there is none.
  static CopilotAgent of(BuildContext context) {
    final agent = maybeOf(context);
    if (agent == null) {
      throw FlutterError(
        'No CopilotAgentScope found in context.\n'
        'Wrap the widgets that read the agent in a CopilotAgentScope.',
      );
    }
    return agent;
  }

  /// Returns the agent of the nearest [CopilotAgentScope] ancestor, or
  /// `null`.
  static CopilotAgent? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CopilotAgentScope>()?.agent;

  @override
  Widget build(BuildContext context) {
    return _CopilotAgentScope(
      agent: CopilotKit.of(context).agent(agentId),
      child: child,
    );
  }
}

class const _CopilotAgentScope({
  required final CopilotAgent agent,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_CopilotAgentScope oldWidget) =>
      agent != oldWidget.agent;
}
