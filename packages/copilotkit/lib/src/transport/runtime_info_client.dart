import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/transport/models/runtime_info.dart';
import 'package:http/http.dart' as http;

/// Reads a Copilot Runtime's `GET /info`.
///
/// Both transports ask the runtime what it is the same way, so they share
/// this class.
class const RuntimeInfoClient({
  /// The runtime's URL, without a trailing slash.
  required final String baseUrl,

  /// Creates the client of each request.
  required final http.Client Function() httpClientFactory,

  /// How long to wait for the runtime's answer.
  required final Duration timeout,
}) {
  /// Creates a client for the runtime at [baseUrl].
  this;

  /// Sends [headers] to the runtime and decodes its answer.
  ///
  /// Throws an [http.ClientException] when the runtime rejects the request,
  /// doesn't answer within the timeout or doesn't answer with a JSON object.
  Future<RuntimeInfo> call({Map<String, String> headers = const {}}) async {
    final url = Uri.parse('$baseUrl/info');
    final httpClient = httpClientFactory();
    try {
      final request = http.Request('GET', url)
        ..headers.addAll({...headers, 'Accept': 'application/json'});
      final response = await _send(httpClient, request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Runtime info failed with status ${response.statusCode}: '
          '${response.body}',
          url,
        );
      }
      return RuntimeInfo.fromJson(_decodeObject(response.body, url));
    } on TimeoutException {
      throw http.ClientException(
        'Runtime info timed out after ${timeout.inMilliseconds}ms.',
        url,
      );
    } finally {
      httpClient.close();
    }
  }

  Future<http.Response> _send(http.Client client, http.Request request) async {
    final streamed = await client.send(request);
    return await http.Response.fromStream(streamed);
  }

  Map<String, Object?> _decodeObject(String body, Uri url) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, Object?>) return json;
    } on FormatException {
      // Reported below, like a body that isn't an object.
    }
    throw http.ClientException('Runtime info is not a JSON object.', url);
  }
}
