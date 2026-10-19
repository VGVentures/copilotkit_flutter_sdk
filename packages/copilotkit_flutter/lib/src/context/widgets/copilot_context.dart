import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/widgets.dart';

/// Shares [value] with the agent while this widget is mounted.
///
/// Adds a context entry on the nearest `CopilotKit` client on mount,
/// updates it when [value] changes and removes it on dispose.
class const CopilotContext({
  /// Tells the agent what [value] is.
  required final String description,

  /// The data shared with the agent: an app model with `toJson`. Give it
  /// value equality (e.g. `Equatable`), or the entry is sent again on every
  /// rebuild.
  required final JsonEncodable value,

  /// The subtree below this widget.
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  /// Creates a widget that shares [value] while mounted.
  this;

  @override
  State<CopilotContext> createState() => _CopilotContextState();
}

class _CopilotContextState extends State<CopilotContext> {
  CopilotKitClient? _client;

  /// The entry added and the client it was added to, so only that entry is
  /// updated or removed.
  (CopilotKitClient, AgentContextEntry)? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = CopilotKit.of(context);
    if (client != _client) {
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
      _client!.updateContext(_entry!.$2.id, widget.value);
    }
  }

  void _add() {
    _remove();
    final entry = AgentContextEntry(
      description: widget.description,
      value: widget.value,
    );
    final client = _client!..addContext(entry);
    _entry = (client, entry);
  }

  void _remove() {
    if (_entry case (final client, final entry)) {
      client.removeContext(entry.id);
    }
    _entry = null;
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
