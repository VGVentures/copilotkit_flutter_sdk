import 'dart:collection';

import 'package:copilotkit/src/tools/frontend_tool.dart';

/// The frontend tools the app registered, by name.
///
/// Tools come and go while the app runs, so this is mutable: a documented
/// exception to the immutability rule.
class ToolRegistry() {
  /// Creates an empty registry.
  this;

  final _tools = <String, FrontendTool<Object?>>{};

  /// The registered tools, by name. A read-only view.
  Map<String, FrontendTool<Object?>> get tools => UnmodifiableMapView(_tools);

  /// The tool registered as [name], or `null`.
  FrontendTool<Object?>? operator [](String name) => _tools[name];

  /// Registers [tool], replacing a tool with the same name.
  void register(FrontendTool<Object?> tool) => _tools[tool.name] = tool;

  /// Unregisters [tool] if it is the tool registered under its name; a
  /// different tool registered later under the same name stays.
  void unregister(FrontendTool<Object?> tool) {
    if (_tools[tool.name] == tool) _tools.remove(tool.name);
  }
}
