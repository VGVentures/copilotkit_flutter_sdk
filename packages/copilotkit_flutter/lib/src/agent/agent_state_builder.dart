import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
/// AgentStateBuilder<Object?>(
///   selector: (state) => state.sharedState,
///   builder: (context, shared) => Text('$shared'),
/// )
/// ```
class const AgentStateBuilder<T>({
  /// Picks the part of the state to build from.
  required final T Function(CopilotAgentState state) selector,

  /// Builds the widget for the selected value.
  required final AgentStateWidgetBuilder<T> builder,
  super.key,
}) extends StatelessWidget {
  /// Creates a widget built from the part of the agent state [selector]
  /// picks.
  this;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<CopilotAgentBloc, CopilotAgentState, T>(
      selector: selector,
      builder: builder,
    );
  }
}
