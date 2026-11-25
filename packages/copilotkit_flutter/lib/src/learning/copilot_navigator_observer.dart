import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/client.dart';
import 'package:flutter/widgets.dart';

/// Records the routes the user moves between as `navigation` trajectory
/// events, while the nearest `CopilotKit` captures a trajectory.
///
/// Add it to the app's navigator, e.g. `MaterialApp.navigatorObservers`,
/// below a `CopilotKit` with `learning` set. Each event is
/// `{from, to, navigationType}`, where the routes are their
/// `RouteSettings.name` and the type is `push`, `replace` or `traverse` (a
/// pop). Routes without a name are sent as `null`.
class CopilotNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that records to `client`, or to the
  /// client of the `CopilotKit` above the navigator when it is `null`.
  new({this._client});

  final CopilotKitClient? _client;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(from: previousRoute, to: route, type: 'push');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(from: oldRoute, to: newRoute, type: 'replace');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(from: route, to: previousRoute, type: 'traverse');

  void _record({
    required Route<dynamic>? from,
    required Route<dynamic>? to,
    required String type,
  }) {
    final navigatorContext = navigator?.context;
    final client =
        _client ??
        (navigatorContext == null
            ? null
            : CopilotKit.maybeRead(navigatorContext));
    client?.recordTrajectoryEvent(TrajectoryBuiltInEvent.navigation, {
      'from': from?.settings.name,
      'to': to?.settings.name,
      'navigationType': type,
    });
  }
}
