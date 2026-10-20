import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/agent/widgets/copilot_agent_scope.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for the [value] an `AgentStateBuilder` selected.
typedef AgentStateWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
);

/// Rebuilds with the part of the agent's state that [selector] picks, and
/// only when that part changes.
///
/// Reads the agent of the nearest `CopilotAgentScope`. For example, the
/// shared state:
///
/// ```dart
/// AgentStateBuilder<SharedState?>(
///   selector: (state) => state.sharedState,
///   builder: (context, shared) => Text('${shared?.toJson()}'),
/// )
/// ```
class const AgentStateBuilder<T>({
  /// Picks the part of the state to build from.
  required final T Function(CopilotKitAgentState state) selector,

  /// Builds the widget for the selected value.
  required final AgentStateWidgetBuilder<T> builder,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget built from the part of the agent state [selector]
  /// picks.
  this;

  @override
  State<AgentStateBuilder<T>> createState() => _AgentStateBuilderState<T>();
}

class _AgentStateBuilderState<T> extends State<AgentStateBuilder<T>> {
  CopilotKitAgent? _agent;
  StreamSubscription<CopilotKitAgentState>? _subscription;
  late T _value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final agent = CopilotAgentScope.of(context);
    if (agent == _agent) return;
    _agent = agent;
    _value = widget.selector(agent.state);
    unawaited(_subscription?.cancel());
    _subscription = agent.stream.listen(_onState);
  }

  @override
  void didUpdateWidget(AgentStateBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selector != oldWidget.selector) {
      _value = widget.selector(_agent!.state);
    }
  }

  void _onState(CopilotKitAgentState state) {
    final value = widget.selector(state);
    if (value == _value) return;
    setState(() => _value = value);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
