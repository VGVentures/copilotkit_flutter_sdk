import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit_flutter/src/client/models/copilot_learning.dart';
import 'package:flutter/widgets.dart';

/// Provides a [CopilotKitClient] to the widget tree.
///
/// Place it near the app root and read the client with [CopilotKit.of].
class CopilotKit extends StatefulWidget {
  /// Creates a client for the runtime at `runtimeUrl` once and disposes it
  /// when this widget is removed. The configuration is read when the client
  /// is created; later changes are ignored.
  const new({
    required Uri this._runtimeUrl,
    required this.child,
    this._headers,
    this._properties,
    this._onError,
    this.learning,
    super.key,
  }) : _client = null;

  /// Provides an existing `client`. The caller owns it: this widget never
  /// disposes it.
  const new value({
    required CopilotKitClient this._client,
    required this.child,
    this.learning,
    super.key,
  }) : _runtimeUrl = null,
       _headers = null,
       _properties = null,
       _onError = null;

  final CopilotKitClient? _client;
  final Uri? _runtimeUrl;
  final HeadersBuilder? _headers;
  final Map<String, Object?>? _properties;
  final CopilotErrorHandler? _onError;

  /// The subtree that can read the client.
  final Widget child;

  /// Captures a trajectory for Automatic Learning while this widget is
  /// mounted, or nothing when `null`.
  ///
  /// The capture starts when the widget mounts, or when this is set, and
  /// stops when it is disposed or set to `null`. Add a
  /// `CopilotNavigatorObserver` to the app's navigator and mark controls
  /// with `CopilotAction` to capture what the user does.
  final CopilotLearning? learning;

  /// Returns the client of the nearest [CopilotKit] ancestor.
  ///
  /// Throws a [FlutterError] if there is none.
  static CopilotKitClient of(BuildContext context) {
    final client = maybeOf(context);
    if (client == null) {
      throw FlutterError(
        'No CopilotKit found in context.\n'
        'Wrap your app (or the part that uses CopilotKit) in a CopilotKit '
        'widget.',
      );
    }
    return client;
  }

  /// Returns the client of the nearest [CopilotKit] ancestor, or `null`.
  static CopilotKitClient? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CopilotKitScope>()?.client;

  /// Returns the client of the nearest [CopilotKit] ancestor, or `null`,
  /// without rebuilding [context] when it changes: for code that runs
  /// outside `build`, like a navigator observer.
  static CopilotKitClient? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_CopilotKitScope>()?.client;

  @override
  State<CopilotKit> createState() => _CopilotKitState();
}

class _CopilotKitState extends State<CopilotKit> {
  CopilotKitClient? _ownedClient;

  CopilotKitClient get _client =>
      widget._client ??
      (_ownedClient ??= CopilotKitClient(
        runtimeUrl: widget._runtimeUrl!,
        headers: widget._headers,
        properties: widget._properties,
        onError: widget._onError,
      ));

  @override
  void initState() {
    super.initState();
    _startLearning();
  }

  @override
  void didUpdateWidget(CopilotKit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.learning == oldWidget.learning) return;
    if (widget.learning == null) {
      unawaited(_client.stopTrajectory());
    } else {
      _startLearning();
    }
  }

  void _startLearning() {
    final learning = widget.learning;
    if (learning == null) return;
    unawaited(_client.startTrajectory(trajectoryId: learning.trajectoryId));
  }

  @override
  void dispose() {
    final client = _ownedClient;
    if (client != null) {
      // Closing the client stops the capture too.
      unawaited(client.close());
    } else if (widget.learning != null) {
      unawaited(_client.stopTrajectory());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CopilotKitScope(client: _client, child: widget.child);
  }
}

class const _CopilotKitScope({
  required final CopilotKitClient client,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_CopilotKitScope oldWidget) =>
      client != oldWidget.client;
}
