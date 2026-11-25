import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/trajectory/models/trajectory_exception.dart';
import 'package:copilotkit/src/trajectory/models/trajectory_grant.dart';
import 'package:http/http.dart' as http;

/// Asks a Copilot Runtime for the grant to capture a trajectory, through
/// `POST /trajectory/{id}/connect`.
///
/// The runtime needs Intelligence and an `identifyUser`, and the project
/// needs trajectories. The request and error shapes mirror
/// `@copilotkit/core` 1.79.
class TrajectoryClient({
  required Uri runtimeUrl,
  Future<Map<String, String>> Function()? headers,
  http.Client Function()? httpClientFactory,
  Duration timeout = const Duration(seconds: 10),
}) {
  /// Creates a client for the runtime at [runtimeUrl], e.g.
  /// `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers of each request, e.g. for auth; the runtime
  /// knows the user from them. A request that gets no answer within
  /// [timeout] fails with `CONNECTION_TIMEOUT`. Each request sends through a
  /// client from `httpClientFactory`, [http.Client.new] by default, closed
  /// after it.
  this;

  static final _code = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  final String _baseUrl = runtimeUrl.toString().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  final Future<Map<String, String>> Function()? _headers = headers;
  final http.Client Function() _httpClientFactory =
      httpClientFactory ?? http.Client.new;
  final Duration _timeout = timeout;

  /// Returns the grant for the trajectory [trajectoryId], a UUID.
  ///
  /// Throws a [TrajectoryException] with the runtime's `code` when it
  /// refuses, e.g. `TRAJECTORIES_NOT_ENABLED`, `INVALID_GRANT` when its
  /// answer isn't a grant, and `CONNECTION_FAILED` or `CONNECTION_TIMEOUT`
  /// when it can't be reached. Only a 5xx, 408, 429 or no answer is
  /// retryable.
  Future<TrajectoryGrant> connect(String trajectoryId) async {
    final url = Uri.parse(
      '$_baseUrl/trajectory/${Uri.encodeComponent(trajectoryId)}/connect',
    );
    final client = _httpClientFactory();
    final http.Response response;
    try {
      final headers = {
        ...?await _headers?.call(),
        'Content-Type': 'application/json',
      };
      response = await client
          .post(url, headers: headers, body: '{}')
          .timeout(_timeout);
    } on TimeoutException {
      throw TrajectoryException(
        code: 'CONNECTION_TIMEOUT',
        message: 'The runtime did not answer within ${_timeout.inSeconds}s.',
        isRetryable: true,
      );
    } on Object catch (error) {
      throw TrajectoryException(
        code: 'CONNECTION_FAILED',
        message: 'Request failed: $error',
        isRetryable: true,
      );
    } finally {
      client.close();
    }
    final status = response.statusCode;
    final body = _decode(response.body);
    if (status < 200 || status >= 300) {
      final code = switch (body) {
        {'code': final String code} when _code.hasMatch(code) => code,
        _ => 'CONNECTION_FAILED',
      };
      throw TrajectoryException(
        code: code,
        message: switch (body) {
          {'message': final String message} => message,
          _ => 'Request failed: $status',
        },
        statusCode: status,
        isRetryable: status >= 500 || status == 408 || status == 429,
      );
    }
    try {
      return TrajectoryGrant.fromJson(body! as Map<String, Object?>);
    } on Object {
      throw TrajectoryException(
        code: 'INVALID_GRANT',
        message: 'The runtime sent an invalid trajectory grant.',
        statusCode: status,
      );
    }
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
