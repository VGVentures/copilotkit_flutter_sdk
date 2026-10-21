import 'dart:collection';

import 'package:copilotkit/src/tools/client_tool.dart';

/// The client tools the app registered, by name.
///
/// Tools come and go while the app runs, so this is mutable: a documented
/// exception to the immutability rule.
///
/// Registering a tool equal to the registered one counts as another
/// registration of it, and the tool stays until each registration is undone.
/// Two owners of one tool, like a widget and its remounted copy, can then
/// each unregister it without removing it from the other.
class ToolRegistry() {
  /// Creates an empty registry.
  this;

  final _tools = <String, ClientTool<Object?>>{};

  /// The number of registrations of each tool in [_tools], by name.
  final _counts = <String, int>{};

  /// The registered tools, by name. A read-only view.
  Map<String, ClientTool<Object?>> get tools => UnmodifiableMapView(_tools);

  /// The tool registered as [name], or `null`.
  ClientTool<Object?>? operator [](String name) => _tools[name];

  /// Registers [tool], replacing a different tool with the same name.
  ///
  /// When [tool] equals the registered one, it is counted as one more
  /// registration of it.
  void register(ClientTool<Object?> tool) {
    if (_tools[tool.name] == tool) {
      _counts.update(tool.name, (count) => count + 1);
      return;
    }
    _tools[tool.name] = tool;
    _counts[tool.name] = 1;
  }

  /// Undoes one registration of [tool] if it is the tool registered under
  /// its name; a different tool registered later under the same name stays.
  ///
  /// Returns whether [tool] was removed: `false` while other registrations
  /// of it remain.
  bool unregister(ClientTool<Object?> tool) {
    if (_tools[tool.name] != tool) return false;
    final count = _counts[tool.name]! - 1;
    if (count > 0) {
      _counts[tool.name] = count;
      return false;
    }
    _tools.remove(tool.name);
    _counts.remove(tool.name);
    return true;
  }
}
