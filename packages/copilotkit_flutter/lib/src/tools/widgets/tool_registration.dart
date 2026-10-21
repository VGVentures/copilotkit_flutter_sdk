/// @docImport 'package:copilotkit_flutter/src/tools/widgets/copilot_human_in_the_loop.dart';
/// @docImport 'package:copilotkit_flutter/src/tools/widgets/copilot_tool.dart';
library;

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Registers [tool] on the nearest [CopilotKit] client while mounted.
///
/// Internal: [CopilotTool] and [CopilotHumanInTheLoop] build it, so the
/// registration rules live in one place.
///
/// Registers [tool] on mount and unregisters it on dispose. A tool that
/// changes is registered first and the old one unregistered after it, so the
/// client never lacks the tool in between: unregistering a human-in-the-loop
/// tool cancels the calls that wait for the user. A tool equal to the
/// registered one changes nothing.
///
/// Each mounted registration counts on the client, so when its subtree
/// remounts, or another widget registers the same tool, the tool stays
/// registered until the last of them is disposed.
@internal
class const ToolRegistration({
  /// The tool to register.
  required final ClientTool<Object?> tool,

  /// The subtree below this widget.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget that registers [tool] while mounted.
  this;

  @override
  State<ToolRegistration> createState() => _ToolRegistrationState();
}

class _ToolRegistrationState extends State<ToolRegistration> {
  CopilotKitClient? _client;

  /// The tool registered and the client it was registered on, so only that
  /// registration is undone.
  (CopilotKitClient, ClientTool<Object?>)? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (client != _client) {
      _client = client;
      _register();
    }
  }

  @override
  void didUpdateWidget(ToolRegistration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tool != oldWidget.tool) _register();
  }

  void _register() {
    final previous = _registered;
    final client = _client!..registerTool(widget.tool);
    _registered = (client, widget.tool);
    if (previous case (final previousClient, final previousTool)) {
      previousClient.unregisterTool(previousTool);
    }
  }

  @override
  void dispose() {
    if (_registered case (final client, final tool)) {
      client.unregisterTool(tool);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
