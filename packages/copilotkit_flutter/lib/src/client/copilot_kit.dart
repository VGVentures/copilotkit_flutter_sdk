import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/copilotkit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// {@template copilot_kit}
/// Provides a [CopilotKitClient] to the widget tree.
///
/// Place it near the app root and read the client with [CopilotKit.of], or
/// with `context.read<CopilotKitClient>()` and `BlocBuilder` as for any bloc.
/// {@endtemplate}
class CopilotKit extends StatefulWidget {
  /// {@macro copilot_kit}
  ///
  /// Creates a client for the runtime at `runtimeUrl` once and disposes it
  /// when this widget is removed.
  ///
  /// `headers` is called before every run, and `onError` on every error, so
  /// closures that read the current token or context stay up to date.
  /// `runtimeUrl` and `properties` are read when the client is created; a
  /// later change is ignored, and fails an assertion in debug mode.
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
      widget._client ?? (_ownedClient ??= _createClient());

  /// A client that reads its callbacks from the current widget, so a rebuild
  /// with new closures takes effect.
  CopilotKitClient _createClient() => CopilotKitClient(
    runtimeUrl: widget._runtimeUrl!,
    headers: () async => await widget._headers?.call() ?? const {},
    properties: widget._properties,
    onError: (error, stackTrace) => widget._onError?.call(error, stackTrace),
  );

  @override
  void didUpdateWidget(CopilotKit oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      _ownedClient == null ||
          (widget._runtimeUrl == oldWidget._runtimeUrl &&
              jsonEncode(widget._properties) ==
                  jsonEncode(oldWidget._properties)),
      'CopilotKit reads runtimeUrl and properties once, when it creates its '
      'client. To use another runtime or other properties, give the '
      'CopilotKit a new key.',
    );
  }

  @override
  void dispose() {
    final client = _ownedClient;
    if (client != null) unawaited(client.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    return _CopilotKitScope(
      client: client,
      child: BlocProvider<CopilotKitClient>.value(
        value: client,
        child: widget.child,
      ),
    );
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
