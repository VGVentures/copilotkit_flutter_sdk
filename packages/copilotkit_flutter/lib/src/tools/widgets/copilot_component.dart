/// @docImport 'package:copilotkit_flutter/src/client/client.dart';
library;

import 'package:ack/ack.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/tools/widgets/copilot_tool.dart';
import 'package:flutter/widgets.dart';

/// Lets the agent show a widget in the chat while this widget is mounted:
/// the Flutter version of `useComponent`.
///
/// Registers a [FrontendTool] named [name] without a handler on the nearest
/// [CopilotKit] client. The agent "calls" it to display the component, each
/// call renders with [builder] in [child], with the arguments decoded by
/// [decode] (`null` while they stream in), and the call's result is `''`.
/// The tool's description starts with [descriptionPrefix], as upstream's
/// does, so the agent knows the tool only shows something.
class const CopilotComponent<T>({
  /// The name the agent calls the component by.
  required final String name,

  /// What the component shows, and when to use it.
  required final String description,

  /// The arguments the agent passes, validated before [builder] sees them.
  required final ObjectSchema parameters,

  /// Decodes the arguments, once they are valid or while they stream in.
  required final T Function(Map<String, Object?> json) decode,

  /// Builds the widget for each call, from its arguments.
  required final FrontendToolWidgetBuilder<T> builder,

  /// The subtree where calls render with [builder].
  required final Widget child,

  /// Whether the agent runs again after showing the component, e.g. to
  /// comment on it. When `false` and the run only showed components, the
  /// turn ends.
  final bool followUp = true,
  super.key,
}) extends StatelessWidget {
  /// Creates a widget that lets the agent show the component [name].
  this;

  /// What every component's description starts with, the same text as
  /// `useComponent` in `@copilotkit/react-core`.
  static String descriptionPrefix(String name) =>
      'Use this tool to display the "$name" component in the chat. This '
      'tool renders a visual UI component for the user.';

  @override
  Widget build(BuildContext context) => CopilotTool(
    tool: FrontendTool(
      name: name,
      description: '${descriptionPrefix(name)} $description',
      parameters: parameters,
      decode: decode,
      followUp: followUp,
    ),
    builder: builder,
    child: child,
  );
}
