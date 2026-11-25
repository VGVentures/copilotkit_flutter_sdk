// cspell:ignore realtime
/// @docImport 'package:copilotkit/src/client/client.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/threads/models/thread_metadata_event.dart';
import 'package:copilotkit/src/threads/models/thread_page.dart';
import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:copilotkit/src/threads/models/threads_error_code.dart';
import 'package:copilotkit/src/threads/models/threads_exception.dart';
import 'package:copilotkit/src/threads/thread_metadata_listener.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';

/// Lists, renames, archives, unarchives and deletes the threads of an agent,
/// through the `/threads` routes of a Copilot Runtime, and follows changes to
/// them live with [watch].
///
/// Listing works on a runtime that keeps threads. Changing a thread needs a
/// runtime with Intelligence: its `RuntimeInfo.threadEndpoints` say which
/// routes it has. A failure throws a [ThreadsException].
///
/// The request and response shapes mirror `@copilotkit/core` 1.79, which is
/// the only description of the routes. The runtime knows the user from the
/// headers, so pass the same `headers` as [CopilotKitClient].
///
/// [CopilotKitClient.threads] provides a client for its runtime.
class ThreadsClient({
  required Uri runtimeUrl,
  Future<Map<String, String>> Function()? headers,
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 15),
  @visibleForTesting
  PhoenixChannelsClient Function(Uri socketUrl, Map<String, String> params)?
  channelFactory,
}) {
  /// Creates a client for the thread routes of the runtime at [runtimeUrl],
  /// e.g. `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers of each request, e.g. for auth. A request
  /// that gets no answer within [timeout] fails with
  /// [ThreadsErrorCode.requestTimeout]. The client sends through [httpClient],
  /// which defaults to [http.Client.new], and [close] closes it.
  /// [channelFactory] replaces the Phoenix client of [watch] in tests.
  this;

  final Uri _baseUrl = Uri.parse(
    '${runtimeUrl.toString().replaceFirst(RegExp(r'/+$'), '')}/threads',
  );
  final Future<Map<String, String>> Function()? _headers = headers;
  final http.Client _httpClient = httpClient ?? http.Client();
  final Duration _timeout = timeout;
  final PhoenixChannelsClient Function(Uri, Map<String, String>)?
  _channelFactory = channelFactory;

  /// Returns a page of the threads of [agentId], newest first.
  ///
  /// Archived threads are left out unless [includeArchived]. At most [limit]
  /// threads come back, as many as the runtime chooses when it is `null`.
  /// Pass the [ThreadPage.nextCursor] of a page as [cursor] to get the next
  /// one. Throws a [ThreadsException] with [ThreadsErrorCode.listFailed] when
  /// the runtime fails.
  Future<ThreadPage> list({
    required String agentId,
    bool includeArchived = false,
    int? limit,
    String? cursor,
  }) async {
    const code = ThreadsErrorCode.listFailed;
    final response = await _send(
      'GET',
      _baseUrl.replace(
        queryParameters: {
          'agentId': agentId,
          if (includeArchived) 'includeArchived': 'true',
          if (limit != null) 'limit': '$limit',
          'cursor': ?cursor,
        },
      ),
      code: code,
    );
    try {
      return ThreadPage.fromJson(_object(response));
    } on Object catch (error) {
      throw _invalid(code, response, 'threads', error);
    }
  }

  /// Gives the thread [threadId] of [agentId] the name [name], and returns
  /// the thread as it is then.
  ///
  /// Throws a [ThreadsException] with [ThreadsErrorCode.mutationFailed] when
  /// the runtime fails, which it also does for a thread it doesn't have.
  Future<ThreadRecord> rename({
    required String agentId,
    required String threadId,
    required String name,
  }) => _update(agentId, threadId, {'name': name});

  /// Archives the thread [threadId] of [agentId], hiding it from the default
  /// list.
  ///
  /// Throws a [ThreadsException] with [ThreadsErrorCode.mutationFailed] when
  /// the runtime fails.
  Future<void> archive({
    required String agentId,
    required String threadId,
  }) async {
    await _send(
      'POST',
      _thread(threadId, 'archive'),
      code: ThreadsErrorCode.mutationFailed,
      body: {'agentId': agentId},
    );
  }

  /// Brings the archived thread [threadId] of [agentId] back into the default
  /// list, and returns the thread as it is then.
  ///
  /// Throws a [ThreadsException] with [ThreadsErrorCode.mutationFailed] when
  /// the runtime fails.
  Future<ThreadRecord> unarchive({
    required String agentId,
    required String threadId,
  }) => _update(agentId, threadId, {'archived': false});

  /// Deletes the thread [threadId] of [agentId] for good.
  ///
  /// Throws a [ThreadsException] with [ThreadsErrorCode.mutationFailed] when
  /// the runtime fails, which it also does for a thread it no longer has.
  Future<void> delete({
    required String agentId,
    required String threadId,
  }) async {
    await _send(
      'DELETE',
      _thread(threadId),
      code: ThreadsErrorCode.mutationFailed,
      body: {'agentId': agentId},
    );
  }

  /// Asks the runtime for a join token of the user's thread metadata channel,
  /// through `POST /threads/subscribe`.
  ///
  /// Throws a [ThreadsException] with [ThreadsErrorCode.subscribeFailed] when
  /// the runtime fails, which a runtime without Intelligence always does.
  Future<String> subscribe() async {
    const code = ThreadsErrorCode.subscribeFailed;
    final response = await _send(
      'POST',
      _baseUrl.replace(pathSegments: [..._baseUrl.pathSegments, 'subscribe']),
      code: code,
      body: const {},
    );
    try {
      return switch (_object(response)) {
        {'joinToken': final String token} when token.isNotEmpty => token,
        _ => throw const FormatException('The body has no joinToken.'),
      };
    } on Object catch (error) {
      throw _invalid(code, response, 'credentials', error);
    }
  }

  /// Follows the user's thread metadata channel, [joinCode] from
  /// [ThreadPage.joinCode], on the real-time socket at [socketUrl], the
  /// runtime's `RuntimeInfo.intelligence.wsUrl`.
  ///
  /// Each socket asks [subscribe] for its token. A socket that drops is
  /// opened again after a growing delay; after 5 failures in a row the stream
  /// emits a [ThreadsException] with [ThreadsErrorCode.realtimeUnavailable]
  /// and ends. The service may push an event more than once, so apply events
  /// in a way that repeating one changes nothing.
  Stream<ThreadMetadataEvent> watch({
    required Uri socketUrl,
    required String joinCode,
  }) => ThreadMetadataListener(
    socketUrl: socketUrl,
    joinCode: joinCode,
    joinToken: subscribe,
    channelFactory: _channelFactory,
  ).events;

  /// Closes the client it sends through.
  void close() => _httpClient.close();

  Future<ThreadRecord> _update(
    String agentId,
    String threadId,
    Map<String, Object?> changes,
  ) async {
    const code = ThreadsErrorCode.mutationFailed;
    final response = await _send(
      'PATCH',
      _thread(threadId),
      code: code,
      body: {'agentId': agentId, ...changes},
    );
    try {
      return ThreadRecord.fromJson(_object(response));
    } on Object catch (error) {
      throw _invalid(code, response, 'thread', error);
    }
  }

  Uri _thread(String threadId, [String? action]) => _baseUrl.replace(
    pathSegments: [..._baseUrl.pathSegments, threadId, ?action],
  );

  Future<http.Response> _send(
    String method,
    Uri url, {
    required ThreadsErrorCode code,
    Map<String, Object?>? body,
  }) async {
    final http.Response response;
    // Completes on a timeout, so the request stops instead of finishing in
    // the background: a rename or delete that gave up must not go through
    // later, while the caller thinks it failed.
    final abort = Completer<void>();
    try {
      final request =
          http.AbortableRequest(method, url, abortTrigger: abort.future)
            ..headers.addAll({
              ...?await _headers?.call(),
              if (body != null) 'Content-Type': 'application/json',
            });
      if (body != null) request.body = jsonEncode(body);
      response = await _exchange(request).timeout(
        _timeout,
        onTimeout: () {
          abort.complete();
          throw TimeoutException(null);
        },
      );
    } on TimeoutException {
      throw ThreadsException(
        code: ThreadsErrorCode.requestTimeout,
        message: 'The runtime did not answer within ${_describe(_timeout)}.',
      );
    } on Object catch (error) {
      throw ThreadsException(code: code, message: 'Request failed: $error');
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw ThreadsException(
        code: code,
        message: _errorOf(response.body) ?? 'Request failed: $status',
        statusCode: status,
      );
    }
    return response;
  }

  /// Sends [request] and reads the whole answer.
  Future<http.Response> _exchange(http.BaseRequest request) async =>
      await http.Response.fromStream(await _httpClient.send(request));

  String _describe(Duration duration) => duration.inSeconds >= 1
      ? '${duration.inSeconds}s'
      : '${duration.inMilliseconds} ms';

  /// The `error` the runtime put in a JSON body, if it did.
  String? _errorOf(String body) {
    try {
      if (jsonDecode(body) case {'error': final String error}) return error;
    } on FormatException {
      // Not JSON: there is no message to give.
    }
    return null;
  }

  Map<String, Object?> _object(http.Response response) =>
      jsonDecode(response.body) as Map<String, Object?>;

  ThreadsException _invalid(
    ThreadsErrorCode code,
    http.Response response,
    String what,
    Object error,
  ) => ThreadsException(
    code: code,
    message: 'The runtime sent invalid $what: $error',
    statusCode: response.statusCode,
  );
}
