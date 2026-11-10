/// @docImport 'package:copilotkit/src/client/client.dart';
library;

import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/memories/models/memory.dart';
import 'package:copilotkit/src/memories/models/memory_error_code.dart';
import 'package:copilotkit/src/memories/models/memory_exception.dart';
import 'package:copilotkit/src/memories/models/memory_mutation_outcome.dart';
import 'package:copilotkit/src/memories/models/memory_scope.dart';
import 'package:copilotkit/src/memories/models/memory_unavailable_exception.dart';
import 'package:copilotkit/src/memories/models/memory_validation_exception.dart';
import 'package:copilotkit/src/memories/models/new_memory.dart';
import 'package:http/http.dart' as http;

/// Lists, recalls, saves, supersedes and retires the memories of the user,
/// through the `/memories` routes of a Copilot Runtime.
///
/// The runtime has these routes only when it has `memory.access` configured
/// and an Intelligence project that is entitled to memory. Every method
/// throws a [MemoryUnavailableException] when it has not, which is not a
/// failure. Other failures throw a [MemoryException], and a value that
/// breaks a limit of the runtime throws a [MemoryValidationException]
/// before anything is sent.
///
/// The request and response shapes mirror `@copilotkit/core` 1.79, which is
/// the only description of the routes. The runtime knows the user from the
/// headers, so pass the same `headers` as [CopilotKitClient].
///
/// [CopilotKitClient.memories] provides a client for its runtime.
class MemoriesClient({
  required Uri runtimeUrl,
  Future<Map<String, String>> Function()? headers,
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 15),
}) {
  /// Creates a client for the memory routes of the runtime at [runtimeUrl],
  /// e.g. `https://host/api/copilotkit`.
  ///
  /// `headers` builds the headers of each request, e.g. for auth. A request
  /// that gets no answer within [timeout] fails with
  /// [MemoryErrorCode.requestTimeout]. The client sends through [httpClient],
  /// which defaults to [http.Client.new], and [close] closes it.
  this;

  /// The most memories a recall returns, whatever limit it is asked for.
  static const maxRecallLimit = 20;

  /// The number of memories a recall returns when it isn't given a limit.
  static const defaultRecallLimit = 5;

  /// The statuses that say the runtime has no memory.
  ///
  /// A missing memory is a 404 too, so the routes of one memory leave it out.
  static const _unavailableStatuses = {403, 404, 422, 501};

  static const _unavailableItemStatuses = {403, 422, 501};

  final String _baseUrl =
      '${runtimeUrl.toString().replaceFirst(RegExp(r'/+$'), '')}/memories';
  final Future<Map<String, String>> Function()? _headers = headers;
  final http.Client _httpClient = httpClient ?? http.Client();
  final Duration _timeout = timeout;

  /// Returns the memories of the user, newest first.
  ///
  /// Retired memories are left out unless [includeInvalidated]. Throws a
  /// [MemoryException] with [MemoryErrorCode.listFailed] when the runtime
  /// fails.
  Future<List<Memory>> list({bool includeInvalidated = false}) async {
    const code = MemoryErrorCode.listFailed;
    final response = await _send(
      'GET',
      includeInvalidated ? '$_baseUrl?includeInvalidated=true' : _baseUrl,
      code: code,
    );
    return _memories(response, code);
  }

  /// Returns the memories that best match [query], best first, each with its
  /// [Memory.score].
  ///
  /// At most [limit] memories come back, [defaultRecallLimit] when it is
  /// `null`, and never more than [maxRecallLimit]. [scope] narrows the recall
  /// to one scope. Throws a [MemoryValidationException] when [query] is blank
  /// or [limit] is not positive, and a [MemoryException] with
  /// [MemoryErrorCode.recallFailed] when the runtime fails.
  Future<List<Memory>> recall(
    String query, {
    int? limit,
    MemoryScope? scope,
  }) async {
    const code = MemoryErrorCode.recallFailed;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const MemoryValidationException('query is blank.');
    }
    if (limit != null && limit < 1) {
      throw const MemoryValidationException('limit is not positive.');
    }
    final response = await _send(
      'POST',
      '$_baseUrl/recall',
      code: code,
      body: {
        'query': trimmed,
        'limit': (limit ?? defaultRecallLimit).clamp(1, maxRecallLimit),
        'scope': ?scope?.wireName,
      },
    );
    return _memories(response, code);
  }

  /// Saves [memory].
  ///
  /// When it is a near-duplicate of a memory the user has, the runtime merges
  /// it into that memory instead: see [MemoryMutationOutcome.isAbsorbed].
  /// Throws a [MemoryValidationException] when [memory] breaks a limit, and a
  /// [MemoryException] with [MemoryErrorCode.mutationFailed] when the
  /// runtime fails.
  Future<MemoryMutationOutcome> save(NewMemory memory) async {
    const code = MemoryErrorCode.mutationFailed;
    memory.validate();
    final response = await _send(
      'POST',
      _baseUrl,
      code: code,
      body: memory.toJson(),
    );
    return _outcome(response, code, retires: false);
  }

  /// Replaces the memory [id] with [memory].
  ///
  /// This retires [id] and stores a new memory with another id, so the id
  /// the app holds is stale afterwards: use [MemoryMutationOutcome.memory].
  /// It is a full replacement, not a patch: a [NewMemory.sourceThreadIds]
  /// left out resets them instead of keeping the old ones. Throws a
  /// [MemoryValidationException] when [memory] breaks a limit, and a
  /// [MemoryException] with [MemoryErrorCode.mutationFailed], status 404
  /// included, when the runtime fails or has no live memory [id].
  Future<MemoryMutationOutcome> supersede(String id, NewMemory memory) async {
    const code = MemoryErrorCode.mutationFailed;
    memory.validate();
    final response = await _send(
      'PATCH',
      _itemUrl(id),
      code: code,
      body: memory.toJson(),
      unavailableStatuses: _unavailableItemStatuses,
    );
    return _outcome(response, code, retires: true);
  }

  /// Retires the memory [id]: the list and a recall no longer return it, but
  /// a list with `includeInvalidated` does.
  ///
  /// Throws a [MemoryException] with [MemoryErrorCode.mutationFailed], status
  /// 404 included, when the runtime fails or has no live memory [id].
  Future<void> retire(String id) async {
    await _send(
      'DELETE',
      _itemUrl(id),
      code: MemoryErrorCode.mutationFailed,
      unavailableStatuses: _unavailableItemStatuses,
    );
  }

  /// Closes the HTTP client. The client can't be used afterwards.
  void close() => _httpClient.close();

  String _itemUrl(String id) => '$_baseUrl/${Uri.encodeComponent(id)}';

  Future<http.Response> _send(
    String method,
    String url, {
    required MemoryErrorCode code,
    Map<String, Object?>? body,
    Set<int> unavailableStatuses = _unavailableStatuses,
  }) async {
    final http.Response response;
    try {
      final headers = await _headers?.call() ?? const {};
      final request = http.Request(method, Uri.parse(url))
        ..headers.addAll({
          ...headers,
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      response = await Future(() async {
        final streamed = await _httpClient.send(request);
        return await http.Response.fromStream(streamed);
      }).timeout(_timeout);
    } on TimeoutException {
      throw MemoryException(
        code: MemoryErrorCode.requestTimeout,
        message: 'The runtime did not answer within ${_timeout.inSeconds}s.',
      );
    } on Object catch (error) {
      throw MemoryException(code: code, message: 'Request failed: $error');
    }
    final status = response.statusCode;
    if (unavailableStatuses.contains(status)) {
      throw MemoryUnavailableException(status);
    }
    if (status < 200 || status >= 300) {
      throw MemoryException(
        code: code,
        message: 'Request failed: $status',
        statusCode: status,
      );
    }
    return response;
  }

  Map<String, Object?> _object(http.Response response, MemoryErrorCode code) {
    try {
      return jsonDecode(response.body) as Map<String, Object?>;
    } on Object {
      throw MemoryException(
        code: code,
        message: 'The runtime sent an invalid body.',
        statusCode: response.statusCode,
      );
    }
  }

  List<Memory> _memories(http.Response response, MemoryErrorCode code) {
    try {
      final memories = _object(response, code)['memories'];
      if (memories is! List) {
        throw const FormatException('The body has no memories list.');
      }
      return List.unmodifiable([
        for (final json in memories)
          Memory.fromJson(json as Map<String, Object?>),
      ]);
    } on Object catch (error) {
      if (error is MemoryException) rethrow;
      throw MemoryException(
        code: code,
        message: 'The runtime sent invalid memories: $error',
        statusCode: response.statusCode,
      );
    }
  }

  MemoryMutationOutcome _outcome(
    http.Response response,
    MemoryErrorCode code, {
    required bool retires,
  }) {
    try {
      final json = _object(response, code);
      final retiredId = json['retiredId'];
      if (retires && (retiredId is! String || retiredId.isEmpty)) {
        throw const FormatException('The body has no retiredId.');
      }
      return MemoryMutationOutcome(
        memory: Memory.fromJson(json),
        isAbsorbed: json['absorbed'] == true,
        retiredId: retires ? retiredId! as String : null,
      );
    } on Object catch (error) {
      if (error is MemoryException) rethrow;
      throw MemoryException(
        code: code,
        message: 'The runtime sent an invalid memory: $error',
        statusCode: response.statusCode,
      );
    }
  }
}
