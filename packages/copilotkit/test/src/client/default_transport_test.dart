import 'dart:convert';
import 'dart:io';

import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/messages.dart';

/// A runtime on the loopback interface, to run [CopilotKitClient] with the
/// transport it picks by itself.
class _Runtime({
  required final int infoStatus,
  required final Object? info,
  required final int runStatus,
  required final String runBody,
  required final String runContentType,
}) {
  final List<String> requests = [];
  late final HttpServer _server;

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      final response = request.response;
      if (request.uri.path == '/info') {
        response
          ..statusCode = infoStatus
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(info));
      } else {
        response
          ..statusCode = runStatus
          ..headers.contentType = ContentType.parse(runContentType)
          ..write(runBody);
      }
      await response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

String _sse(List<Map<String, Object?>> events) =>
    events.map((event) => 'data: ${jsonEncode(event)}\n\n').join();

void main() {
  group('the transport CopilotKitClient picks by itself', () {
    late _Runtime runtime;
    late CopilotKitClient client;
    late List<Object> errors;

    Future<void> start({
      int infoStatus = 200,
      Object? info = const {'mode': 'sse'},
      int runStatus = 200,
      String runBody = '',
      String runContentType = 'text/event-stream',
    }) async {
      runtime = _Runtime(
        infoStatus: infoStatus,
        info: info,
        runStatus: runStatus,
        runBody: runBody,
        runContentType: runContentType,
      );
      await runtime.start();
      errors = [];
      client = CopilotKitClient(
        runtimeUrl: runtime.url,
        onError: (error, _) => errors.add(error),
      );
    }

    tearDown(() async {
      await client.close();
      await runtime.stop();
    });

    test('streams over SSE when the runtime is in SSE mode', () async {
      await start(
        runBody: _sse([
          {'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'},
          {'type': 'TEXT_MESSAGE_START', 'messageId': 'm', 'role': 'assistant'},
          {'type': 'TEXT_MESSAGE_CONTENT', 'messageId': 'm', 'delta': 'Hello'},
          {'type': 'TEXT_MESSAGE_END', 'messageId': 'm'},
          {'type': 'RUN_FINISHED', 'threadId': 't', 'runId': 'r'},
        ]),
      );

      await client.runAgent(
        'default',
        message: const UserMessage(id: 'u1', content: 'Hi'),
      );

      expect(textOf(client.agent('default').state.messages.last), 'Hello');
      expect(runtime.requests, ['GET /info', 'POST /agent/default/run']);
      expect(errors, isEmpty);
    });

    test('runs over Intelligence when the runtime says so', () async {
      await start(
        info: const {'mode': 'intelligence'},
        runStatus: 409,
        runBody: jsonEncode({'error': 'Thread lock denied'}),
        runContentType: 'application/json',
      );

      await client.runAgent(
        'default',
        message: const UserMessage(id: 'u1', content: 'Hi'),
      );

      expect(errors, [
        const ThreadLockedException(message: 'Thread lock denied'),
      ]);
      expect(runtime.requests, ['GET /info', 'POST /agent/default/run']);
    });

    test('falls back to SSE and reports it when /info fails', () async {
      await start(
        infoStatus: 500,
        info: 'down',
        runBody: _sse([
          {'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'},
          {'type': 'RUN_FINISHED', 'threadId': 't', 'runId': 'r'},
        ]),
      );

      await client.runAgent(
        'default',
        message: const UserMessage(id: 'u1', content: 'Hi'),
      );

      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('Runtime info failed'));
      expect(runtime.requests, ['GET /info', 'POST /agent/default/run']);
      expect(client.agent('default').state.error, isNull);
    });
  });
}
