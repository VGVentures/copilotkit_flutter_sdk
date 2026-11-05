// Local stand-in for an Intelligence runtime, so the spike client can be
// exercised without a cloud project. It mimics the contract read from
// `@copilotkit/core` 1.79 (REST credentials, then a Phoenix v2 channel with
// `ag_ui_event` frames, `stop_run`, and a 409 for a thread that has run).
//
// NOT a source of truth for fixtures: only a real runtime is.
//
// Usage: fvm dart run tool/fake_intelligence_server.dart [--port 8300]
// cspell:ignore realtime
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final portIndex = arguments.indexOf('--port');
  final port = portIndex >= 0 ? int.parse(arguments[portIndex + 1]) : 8300;
  final server = await HttpServer.bind('127.0.0.1', port);
  print('fake intelligence runtime: http://127.0.0.1:$port/api/copilotkit');
  final usedThreads = <String>{};
  final tokens = <String, String>{};

  await for (final request in server) {
    final path = request.uri.path;
    if (request.method == 'POST' && path.endsWith('/run')) {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      final threadId = body['threadId']! as String;
      if (!usedThreads.add(threadId)) {
        request.response.statusCode = 409;
        await request.response.close();
        continue;
      }
      final runId = body['runId']! as String;
      final token = 'tok-$runId';
      tokens[token] = threadId;
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'threadId': threadId,
            'runId': runId,
            'joinToken': token,
            'realtime': {
              'clientUrl': 'ws://127.0.0.1:$port/socket',
              'topic': 'thread:$threadId',
            },
          }),
        );
      await request.response.close();
    } else if (path == '/socket/websocket') {
      if (!tokens.containsKey(request.uri.queryParameters['join_token'])) {
        request.response.statusCode = 403;
        await request.response.close();
        continue;
      }
      unawaited(_serve(await WebSocketTransformer.upgrade(request)));
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }
}

Future<void> _serve(WebSocket socket) async {
  String? topic;
  String? joinRef;
  String? runId;
  var stopped = false;

  void send(String event, Map<String, Object?> payload) =>
      socket.add(jsonEncode([joinRef, null, topic, event, payload]));

  await for (final raw in socket) {
    final frame = jsonDecode(raw as String) as List<Object?>;
    final ref = frame[1] as String?;
    final event = frame[3]! as String;
    final payload = (frame[4]! as Map).cast<String, Object?>();
    if (event == 'heartbeat') {
      socket.add(
        jsonEncode([
          null,
          ref,
          'phoenix',
          'phx_reply',
          {'status': 'ok', 'response': <String, Object?>{}},
        ]),
      );
    } else if (event == 'phx_join') {
      topic = frame[2]! as String;
      joinRef = frame[0] as String?;
      runId = payload['run_id'] as String?;
      socket.add(
        jsonEncode([
          joinRef,
          ref,
          topic,
          'phx_reply',
          {'status': 'ok', 'response': <String, Object?>{}},
        ]),
      );
      unawaited(() async {
        final thread = topic!.substring('thread:'.length);
        // The runner stamps routing fields on every event.
        Map<String, Object?> stamp(Map<String, Object?> e) => {
          ...e,
          'thread_id': thread,
          'run_id': runId,
        };
        send(
          'ag_ui_event',
          stamp({'type': 'RUN_STARTED', 'threadId': thread, 'runId': runId}),
        );
        send(
          'ag_ui_event',
          stamp({
            'type': 'TEXT_MESSAGE_START',
            'messageId': 'm1',
            'role': 'assistant',
            'threadId': thread,
            'runId': runId,
          }),
        );
        for (final word in ['Hello', ' from', ' the', ' fake', ' runtime']) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (stopped) return;
          send(
            'ag_ui_event',
            stamp({
              'type': 'TEXT_MESSAGE_CONTENT',
              'messageId': 'm1',
              'delta': word,
              'threadId': thread,
              'runId': runId,
            }),
          );
        }
        send(
          'ag_ui_event',
          stamp({
            'type': 'TEXT_MESSAGE_END',
            'messageId': 'm1',
            'threadId': thread,
            'runId': runId,
          }),
        );
        send(
          'ag_ui_event',
          stamp({'type': 'RUN_FINISHED', 'threadId': thread, 'runId': runId}),
        );
      }());
    } else if (event == 'stop_run') {
      stopped = true;
      socket.add(
        jsonEncode([
          joinRef,
          ref,
          topic,
          'phx_reply',
          {'status': 'ok', 'response': <String, Object?>{}},
        ]),
      );
      send('ag_ui_event', {
        'type': 'RUN_FINISHED',
        'threadId': topic!.substring('thread:'.length),
        'runId': runId,
        'thread_id': topic.substring('thread:'.length),
        'run_id': runId,
      });
    }
  }
}
