// Spike for #72: one run against an Intelligence runtime, end to end.
//
// Usage:
//   fvm dart run tool/intelligence_round_trip.dart \
//     --url http://localhost:8200/api/copilotkit \
//     [--agent default] [--message "Hello"] [--thread-id <id>] \
//     [--header "Authorization=Bearer ..."] \
//     [--tool true] [--conflict true] \
//     [--stop-after <n>] [--stop-via channel|rest] \
//     [--record test/fixtures/intelligence_text_run.jsonl] [--note "..."]
//
// Steps, mirroring `@copilotkit/core` 1.79 `IntelligenceAgent`:
//   1. POST {url}/agent/{id}/run -> {threadId, runId, joinToken, realtime}.
//      A 409 means the thread already has a run (thread lock).
//   2. Open realtime.clientUrl with `join_token`, join realtime.topic with
//      {stream_mode: "run", run_id}.
//   3. Print each `ag_ui_event` (routing fields stripped) until RUN_FINISHED
//      or RUN_ERROR.
//
// --tool sends the example's showWeather frontend tool.
// --conflict sends a second run on the same thread while the first is active,
// to record the thread-lock 409.
// --stop-after <n> stops the run after n events, over the channel
// (`stop_run` push) or over REST (`POST /agent/{id}/stop/{threadId}`).
// --record writes a fixture: a `{"fixture": {...}}` header line, then the
// credentials response, every channel frame and every stop exchange as JSONL.
// The join token and the account ids are redacted.
// cspell:ignore realtime
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'phoenix_client.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.url == null) {
    stderr.writeln(
      'usage: intelligence_round_trip.dart --url <runtimeUrl> '
      '[--agent <id>] [--message <text>] [--thread-id <id>]',
    );
    exit(64);
  }
  exit(await _Spike(options).run());
}

class const _Options({
  required final String? url,
  required final String agent,
  required final String message,
  required final String threadId,
  required final Map<String, String> headers,
  required final String? record,
  required final int? stopAfter,
  required final String stopVia,
  required final bool tool,
  required final bool conflict,
  required final String? note,
}) {
  factory parse(List<String> arguments) {
    final values = <String, String>{};
    final headers = <String, String>{};
    for (var i = 0; i + 1 < arguments.length; i += 2) {
      final key = arguments[i].replaceFirst('--', '');
      if (key == 'header') {
        final parts = arguments[i + 1].split('=');
        headers[parts.first] = parts.skip(1).join('=');
      } else {
        values[key] = arguments[i + 1];
      }
    }
    final tool = values['tool'] == 'true';
    return _Options(
      url: values['url'],
      agent: values['agent'] ?? 'default',
      message:
          values['message'] ??
          (tool ? 'Show me the weather in Lima.' : 'Say hello in five words.'),
      threadId: values['thread-id'] ?? const Uuid().v4(),
      headers: headers,
      record: values['record'],
      stopAfter: int.tryParse(values['stop-after'] ?? ''),
      stopVia: values['stop-via'] ?? 'channel',
      tool: tool,
      conflict: values['conflict'] == 'true',
      note: values['note'],
    );
  }
}

class _Spike(final _Options options) {
  /// Placeholder tool from `example/lib/demo/widgets/weather_demo.dart`.
  static const _showWeather = <String, Object?>{
    'name': 'showWeather',
    'description': 'Show the current weather for a city on the user screen.',
    'parameters': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'description': 'City name, e.g. Lima'},
      },
      'required': ['city'],
    },
  };

  /// Keys whose values identify the account or authorize the socket.
  static const _redacted = {
    'joinToken',
    'join_token',
    'organization_id',
    'user_id',
  };

  final _recorded = <Map<String, Object?>>[];

  /// The stop request in flight, awaited so its answer is recorded.
  Future<void>? _stopping;

  String get _base => options.url!.replaceFirst(RegExp(r'/+$'), '');

  /// Returns the process exit code.
  Future<int> run() async {
    final runId = const Uuid().v4();
    final runtimeVersion = await _runtimeVersion();

    // 1. Credentials.
    final response = await _postRun(runId);
    print('POST run -> ${response.statusCode}');
    if (response.statusCode == 409) {
      print('Thread ${options.threadId} is locked (409).');
      _record('http', {
        'step': 'run',
        'status': 409,
        'body': _decode(response.body),
      });
      await _flush(runtimeVersion);
      return 2;
    }
    if (response.statusCode != 200) {
      print(response.body);
      return 1;
    }
    final credentials = _validate(jsonDecode(response.body));
    print(
      'credentials: thread=${credentials.threadId} run=${credentials.runId} '
      'topic=${credentials.topic} url=${credentials.clientUrl}',
    );
    _record('http', {
      'step': 'run',
      'status': 200,
      'body': {
        'threadId': credentials.threadId,
        'runId': credentials.runId,
        'joinToken': credentials.joinToken,
        'realtime': {
          'clientUrl': credentials.clientUrl.toString(),
          'topic': credentials.topic,
        },
      },
    });

    // A second run on the same thread while the first is active.
    if (options.conflict) {
      final second = await _postRun(const Uuid().v4());
      print('POST second run on the same thread -> ${second.statusCode}');
      _record('http', {
        'step': 'second-run-same-thread',
        'status': second.statusCode,
        'body': _decode(second.body),
      });
    }

    // 2. Join the channel.
    final client = PhoenixClient(
      clientUrl: credentials.clientUrl,
      params: {'join_token': credentials.joinToken},
    );
    final finished = Completer<int>();
    var seen = 0;
    client.events.listen(
      (frame) {
        _record('frame', {'event': frame.event, 'payload': frame.payload});
        if (frame.event != 'ag_ui_event') {
          print('· ${frame.event}');
          return;
        }
        final event = _strip(frame.payload);
        print(jsonEncode(event));
        seen++;
        final type = event['type'];
        if (options.stopAfter == seen) {
          _stopping = _stop(client, credentials);
        }
        if (type == 'RUN_FINISHED' && !finished.isCompleted) {
          finished.complete(0);
        } else if (type == 'RUN_ERROR' && !finished.isCompleted) {
          finished.complete(3);
        }
      },
      onError: (Object error) {
        _record('socket-error', {'error': '$error'});
        if (!finished.isCompleted) finished.complete(4);
        print('socket error: $error');
      },
    );
    try {
      await client.open();
      final joined = await client.join(credentials.topic, {
        'stream_mode': 'run',
        'run_id': credentials.runId,
      });
      print('joined: ${jsonEncode(joined)}');
      final wait = options.stopAfter == null
          ? const Duration(minutes: 2)
          : const Duration(seconds: 25);
      final code = await finished.future.timeout(wait);
      print(code == 0 ? 'RUN_FINISHED reached' : 'ended with code $code');
      return code;
    } on TimeoutException {
      print('no terminal event before the timeout');
      _record('timeout', {'note': 'no terminal event before the timeout'});
      return 5;
    } finally {
      await _stopping;
      await client.close();
      await _flush(runtimeVersion);
    }
  }

  Future<http.Response> _postRun(String runId) => http.post(
    Uri.parse('$_base/agent/${Uri.encodeComponent(options.agent)}/run'),
    headers: {'Content-Type': 'application/json', ...options.headers},
    body: jsonEncode({
      'threadId': options.threadId,
      'runId': runId,
      'state': <String, Object?>{},
      'messages': [
        {'id': const Uuid().v4(), 'role': 'user', 'content': options.message},
      ],
      'tools': options.tool ? [_showWeather] : <Object?>[],
      'context': <Object?>[],
      'forwardedProps': <String, Object?>{},
    }),
  );

  /// Stops the run over the channel or over REST, and records the answer.
  Future<void> _stop(PhoenixClient client, _Credentials credentials) async {
    if (options.stopVia == 'rest') {
      final response = await http.post(
        Uri.parse(
          '$_base/agent/${Uri.encodeComponent(options.agent)}'
          '/stop/${Uri.encodeComponent(credentials.threadId)}',
        ),
        headers: {'Content-Type': 'application/json', ...options.headers},
        body: jsonEncode({'runId': credentials.runId}),
      );
      print('stop over REST -> ${response.statusCode} ${response.body}');
      _record('http', {
        'step': 'stop-rest',
        'status': response.statusCode,
        'body': _decode(response.body),
      });
      return;
    }
    try {
      final reply = await client.push(credentials.topic, 'stop_run', {
        'run_id': credentials.runId,
      });
      print('stop_run acknowledged: ${jsonEncode(reply)}');
      _record('push', {'event': 'stop_run', 'status': 'ok', 'reply': reply});
    } on Object catch (error) {
      print('stop_run failed: $error');
      _record('push', {
        'event': 'stop_run',
        'status': 'error',
        'error': '$error',
      });
    }
  }

  /// The runtime's version, from `GET /info`, for the fixture header.
  Future<String> _runtimeVersion() async {
    try {
      final info = await http.get(
        Uri.parse('$_base/info'),
        headers: options.headers,
      );
      final body = jsonDecode(info.body);
      return body is Map<String, Object?> && body['version'] is String
          ? body['version']! as String
          : 'unknown';
    } on Object {
      return 'unknown';
    }
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  _Credentials _validate(Object? json) {
    final map = json is Map<String, Object?> ? json : <String, Object?>{};
    final realtime = map['realtime'];
    String need(Object? value, String name) {
      if (value is String && value.isNotEmpty) return value;
      throw FormatException('missing $name');
    }

    final rt = realtime is Map<String, Object?>
        ? realtime
        : const <String, Object?>{};
    return _Credentials(
      threadId: map['threadId'] as String? ?? options.threadId,
      runId: need(map['runId'], 'runId'),
      joinToken: need(map['joinToken'], 'joinToken'),
      clientUrl: Uri.parse(need(rt['clientUrl'], 'realtime.clientUrl')),
      topic: need(rt['topic'], 'realtime.topic'),
    );
  }

  /// Port of `stripIntelligenceRoutingFields`: the runner stamps
  /// `thread_id`/`run_id` (and `threadId`/`runId` on events that don't
  /// declare them) on every event. Only RUN_STARTED/RUN_FINISHED keep theirs.
  Map<String, Object?> _strip(Map<String, Object?> event) {
    final keepIdentity =
        event['type'] == 'RUN_STARTED' || event['type'] == 'RUN_FINISHED';
    final copy = {...event}
      ..remove('thread_id')
      ..remove('run_id');
    if (!keepIdentity) {
      copy
        ..remove('threadId')
        ..remove('runId');
    }
    return copy;
  }

  void _record(String kind, Map<String, Object?> data) =>
      _recorded.add({'kind': kind, ...data});

  /// Copies [value], replacing what identifies the account or the socket.
  Object? _redact(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key as String: _redacted.contains(entry.key)
              ? '<redacted>'
              : _redact(entry.value),
      };
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  Future<void> _flush(String runtimeVersion) async {
    final path = options.record;
    if (path == null) return;
    final lines = [
      jsonEncode({
        'fixture': {
          'source': 'recorded',
          'mode': 'intelligence',
          'runtimeVersion': runtimeVersion,
          'recordedOn': DateTime.now().toUtc().toIso8601String().substring(
            0,
            10,
          ),
          'message': options.message,
          if (options.tool) 'tools': ['showWeather'],
          if (options.note != null) 'note': options.note,
        },
      }),
      ..._recorded.map((entry) => jsonEncode(_redact(entry))),
    ];
    await File(path).writeAsString('${lines.join('\n')}\n');
    print('recorded ${_recorded.length} entries to $path');
  }
}

class const _Credentials({
  required final String threadId,
  required final String runId,
  required final String joinToken,
  required final Uri clientUrl,
  required final String topic,
});
