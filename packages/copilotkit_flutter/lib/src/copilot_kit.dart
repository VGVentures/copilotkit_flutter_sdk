import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/widgets.dart';

/// {@template copilot_kit}
/// Provides a [CopilotKitClient] to the widget tree.
///
/// Place it near the app root and read the client with [CopilotKit.of].
/// {@endtemplate}
class CopilotKit extends StatefulWidget {
  /// {@macro copilot_kit}
  ///
  /// Creates a client for the runtime at [_runtimeUrl] once and disposes it
  /// when this widget is removed. The configuration is read when the client
  /// is created; later changes are ignored.
  const new({
    required Uri this._runtimeUrl,
    required this.child,
    this._headers,
    this._properties = const {},
    this._onError,
    super.key,
  }) : _client = null;

  /// {@macro copilot_kit}
  ///
  /// Provides an existing [_client]. The caller owns it: this widget never
  /// disposes it.
  const new value({
    required CopilotKitClient this._client,
    required this.child,
    super.key,
  }) : _runtimeUrl = null,
       _headers = null,
       _properties = const {},
       _onError = null;

  final CopilotKitClient? _client;
  final Uri? _runtimeUrl;
  final HeadersBuilder? _headers;
  final Map<String, Object?> _properties;
  final CopilotErrorHandler? _onError;

  /// The subtree that can read the client.
  final Widget child;

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
  void dispose() {
    final client = _ownedClient;
    if (client != null) unawaited(client.dispose());
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
      !identical(client, oldWidget.client);
}
