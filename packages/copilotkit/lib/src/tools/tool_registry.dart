import 'dart:collection';

import 'package:copilotkit/src/tools/client_tool.dart';

/// The client tools the app registered, by name.
///
/// Tools come and go while the app runs, so this is mutable: a documented
/// exception to the immutability rule.
class ToolRegistry() {
  /// Creates an empty registry.
  this;

  final _tools = <String, ClientTool<Object?>>{};

  /// The registered tools, by name. A read-only view.
  Map<String, ClientTool<Object?>> get tools => UnmodifiableMapView(_tools);

  /// The tool registered as [name], or `null`.
  ClientTool<Object?>? operator [](String name) => _tools[name];

  /// Registers [tool], replacing a tool with the same name.
  void register(ClientTool<Object?> tool) => _tools[tool.name] = tool;

  /// Unregisters [tool] if it is the tool registered under its name; a
  /// different tool registered later under the same name stays.
  ///
  /// Returns whether [tool] was unregistered.
  bool unregister(ClientTool<Object?> tool) {
    if (_tools[tool.name] != tool) return false;
    _tools.remove(tool.name);
    return true;
  }
}
