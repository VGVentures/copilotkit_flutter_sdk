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

  /// How many times the tool under each name was registered and not
  /// unregistered yet.
  final _counts = <String, int>{};

  /// The registered tools, by name.
  ///
  /// A read-only view.
  Map<String, ClientTool<Object?>> get tools => UnmodifiableMapView(_tools);

  /// The tool registered as [name], or `null`.
  ClientTool<Object?>? operator [](String name) => _tools[name];

  /// Registers [tool], replacing a different tool with the same name.
  ///
  /// Registering a tool equal to the registered one counts as another
  /// registration of it, e.g. by a second widget: it stays until each of
  /// them unregisters it.
  void register(ClientTool<Object?> tool) {
    final name = tool.name;
    _counts[name] = _tools[name] == tool ? _counts[name]! + 1 : 1;
    _tools[name] = tool;
  }

  /// Undoes one registration of [tool] if it is the tool registered under
  /// its name; a different tool registered later under the same name stays.
  ///
  /// Returns whether [tool] is gone: `false` when it wasn't registered, or
  /// when an equal tool is still registered by someone else.
  bool unregister(ClientTool<Object?> tool) {
    final name = tool.name;
    if (_tools[name] != tool) return false;
    final count = _counts[name]! - 1;
    if (count > 0) {
      _counts[name] = count;
      return false;
    }
    _counts.remove(name);
    _tools.remove(name);
    return true;
  }
}
