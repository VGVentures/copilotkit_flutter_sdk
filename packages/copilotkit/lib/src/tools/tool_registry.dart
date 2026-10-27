import 'dart:collection';

import 'package:copilotkit/src/tools/client_tool.dart';

/// The client tools the app registered, by name.
///
/// Tools come and go while the app runs, so this is mutable: a documented
/// exception to the immutability rule.
///
/// Each distinct tool under a name keeps its own count of registrations,
/// and the tool registered last is the one in use. A tool stays until each
/// of its registrations is undone, so two owners of one tool, like a widget
/// and its remounted copy, can each unregister it without removing it from
/// the other, even when one of them registers a different tool in between.
class ToolRegistry() {
  /// Creates an empty registry.
  this;

  /// The tool in use under each name: the last one registered.
  final _tools = <String, ClientTool<Object?>>{};

  /// The registrations of each name, oldest first; the last is in use.
  final _registrations = <String, List<_Registration>>{};

  /// The registered tools, by name. A read-only view.
  Map<String, ClientTool<Object?>> get tools => UnmodifiableMapView(_tools);

  /// The tool registered as [name], or `null`.
  ClientTool<Object?>? operator [](String name) => _tools[name];

  /// Registers [tool]; it replaces the tool in use under its name.
  ///
  /// When [tool] equals a tool already registered under its name, it is
  /// counted as one more registration of that tool.
  void register(ClientTool<Object?> tool) {
    final registrations = _registrations.putIfAbsent(tool.name, () => []);
    final index = registrations.indexWhere((r) => r.tool == tool);
    final registration = index < 0
        ? _Registration(tool)
        : registrations.removeAt(index);
    registrations.add(registration..count += 1);
    _tools[tool.name] = registration.tool;
  }

  /// Undoes one registration of [tool].
  ///
  /// Once each registration of [tool] is undone, the tool registered before
  /// it under the same name, if any, is used again.
  ///
  /// Returns whether its name was removed: `false` while any tool remains
  /// registered under it, or when [tool] is not registered.
  bool unregister(ClientTool<Object?> tool) {
    final registrations = _registrations[tool.name];
    if (registrations == null) return false;
    final index = registrations.indexWhere((r) => r.tool == tool);
    if (index < 0) return false;
    if (--registrations[index].count > 0) return false;
    registrations.removeAt(index);
    if (registrations.isNotEmpty) {
      _tools[tool.name] = registrations.last.tool;
      return false;
    }
    _tools.remove(tool.name);
    _registrations.remove(tool.name);
    return true;
  }
}

/// A distinct tool under a name and how many times it is registered.
class _Registration(final ClientTool<Object?> tool) {
  int count = 0;
}
