import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/copilot_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Registers [tool] on the nearest `CopilotKit` client while mounted.
///
/// Internal: `CopilotTool` and `CopilotHumanInTheLoop` build it, so the
/// registration rules live in one place.
///
/// Adds `ToolRegistered` on mount and `ToolUnregistered` on dispose. A tool
/// that changes is registered first and the old one unregistered after it,
/// so the client never lacks the tool in between: unregistering a
/// human-in-the-loop tool cancels the calls that wait for the user. A tool
/// equal to the registered one changes nothing, and the client keeps the
/// instance it has.
@internal
class const ToolRegistration({
  /// The tool to register.
  required final ClientTool tool,

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
  CopilotKitBloc? _client;

  /// The tool instance registered and the client it was registered on, so
  /// only that registration is undone.
  (CopilotKitBloc, ClientTool)? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
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
    final client = _client!..add(ToolRegistered(widget.tool));
    _registered = (client, widget.tool);
    if (previous case (final previousClient, final previousTool)) {
      previousClient.add(ToolUnregistered(previousTool));
    }
  }

  @override
  void dispose() {
    if (_registered case (final client, final tool)) {
      client.add(ToolUnregistered(tool));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
