import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/copilot_kit.dart';
import 'package:flutter/widgets.dart';

/// {@template copilot_context}
/// Shares [value] with the agent while this widget is mounted.
///
/// Adds a context entry on the nearest `CopilotKit` client on mount, updates
/// it when [value] changes and removes it on dispose. [value] must be
/// JSON-encodable.
/// {@endtemplate}
class const CopilotContext({
  /// Tells the agent what [value] is.
  required final String description,

  /// The data shared with the agent.
  required final Object? value,

  /// The subtree below this widget.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// {@macro copilot_context}
  this;

  @override
  State<CopilotContext> createState() => _CopilotContextState();
}

class _CopilotContextState extends State<CopilotContext> {
  CopilotKitClient? _client;
  AgentContextEntry? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (!identical(client, _client)) {
      _client = client;
      _add();
    }
  }

  @override
  void didUpdateWidget(CopilotContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.description != oldWidget.description) {
      _add();
    } else if (widget.value != oldWidget.value) {
      _entry!.update(widget.value);
    }
  }

  void _add() {
    _entry?.remove();
    _entry = _client!.addContext(widget.description, widget.value);
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
