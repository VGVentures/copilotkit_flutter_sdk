import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:copilotkit/src/threads/models/threads_error_code.dart';
import 'package:copilotkit/src/threads/models/threads_exception.dart';
import 'package:copilotkit/src/threads/threads_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/threads_fixture.dart';

class _MockHttpClient extends Mock implements http.Client;

void main() {
  group(ThreadsClient, () {
    late List<http.Request> sent;
    late Future<http.Response> Function(http.Request request) answer;
    late ThreadsClient client;

    ThreadsClient build({
      Uri? runtimeUrl,
      Duration timeout = const Duration(seconds: 15),
      Future<Map<String, String>> Function()? headers,
    }) => ThreadsClient(
      runtimeUrl: runtimeUrl ?? Uri.parse('http://runtime.test/api/copilotkit'),
      headers: headers ?? () async => {'Authorization': 'Bearer token'},
      httpClient: MockClient((request) {
        sent.add(request);
        return answer(request);
      }),
      timeout: timeout,
    );

    void reply(int status, [Object? body]) =>
        answer = (_) async =>
            http.Response(body is String ? body : jsonEncode(body), status);

    Map<String, Object?> sentBody() =>
        jsonDecode(sent.single.body) as Map<String, Object?>;

    setUp(() {
      sent = [];
      reply(200, <String, Object?>{});
      client = build();
    });

    group('list', () {
      test('asks for the threads of the agent', () async {
        reply(200, threadsBody('list'));

        final page = await client.list(agentId: 'default');

        final request = sent.single;
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse(
            'http://runtime.test/api/copilotkit/threads?agentId=default',
          ),
        );
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers, isNot(contains('Content-Type')));
        expect(page.threads, hasLength(2));
        expect(page.hasNext, isTrue);
      });

      test('passes archived, limit and cursor on', () async {
        reply(200, threadsBody('list-page-2'));

        await client.list(
          agentId: 'a b',
          includeArchived: true,
          limit: 1,
          cursor: 'c1',
        );

        expect(sent.single.url.queryParameters, {
          'agentId': 'a b',
          'includeArchived': 'true',
          'limit': '1',
          'cursor': 'c1',
        });
      });

      test('ignores a trailing slash in the runtime url', () async {
        client = build(runtimeUrl: Uri.parse('http://runtime.test/api/'));
        reply(200, threadsBody('list'));

        await client.list(agentId: 'default');

        expect(sent.single.url.path, '/api/threads');
      });

      test('sends no headers when it has no builder', () async {
        client = ThreadsClient(
          runtimeUrl: Uri.parse('http://runtime.test/api'),
          httpClient: MockClient((request) async {
            sent.add(request);
            return http.Response(jsonEncode(threadsBody('list')), 200);
          }),
        );

        await client.list(agentId: 'default');

        expect(sent.single.headers, isNot(contains('Authorization')));
      });

      test('fails with the message the runtime gave', () async {
        final recorded = threadsExchange('list-no-agent');
        reply(recorded['status']! as int, recorded['body']);

        await expectLater(
          client.list(agentId: ''),
          throwsA(
            const ThreadsException(
              code: ThreadsErrorCode.listFailed,
              message: 'Valid agentId query param is required',
              statusCode: 400,
            ),
          ),
        );
      });

      test('fails with the status when the answer has no message', () async {
        reply(503, 'down');

        await expectLater(
          client.list(agentId: 'default'),
          throwsA(
            isA<ThreadsException>()
                .having((e) => e.message, 'message', 'Request failed: 503')
                .having((e) => e.isRetryable, 'isRetryable', isTrue),
          ),
        );
      });

      test('fails when the body is not the threads of a page', () async {
        for (final body in [
          '[]',
          'not json',
          '{"nextCursor": null}',
          '{"threads": [{"id": 1}]}',
        ]) {
          reply(200, body);

          await expectLater(
            client.list(agentId: 'default'),
            throwsA(
              isA<ThreadsException>()
                  .having((e) => e.code, 'code', ThreadsErrorCode.listFailed)
                  .having(
                    (e) => e.message,
                    'message',
                    startsWith('The runtime sent invalid threads'),
                  )
                  .having((e) => e.statusCode, 'statusCode', 200),
            ),
            reason: body,
          );
        }
      });

      test('fails when the request cannot be sent', () async {
        answer = (_) async => throw http.ClientException('offline');

        await expectLater(
          client.list(agentId: 'default'),
          throwsA(
            isA<ThreadsException>()
                .having((e) => e.code, 'code', ThreadsErrorCode.listFailed)
                .having((e) => e.message, 'message', contains('offline'))
                .having((e) => e.statusCode, 'statusCode', isNull),
          ),
        );
      });

      test('fails when the headers cannot be built', () async {
        client = build(headers: () async => throw StateError('no token'));

        await expectLater(
          client.list(agentId: 'default'),
          throwsA(
            isA<ThreadsException>().having(
              (e) => e.message,
              'message',
              contains('no token'),
            ),
          ),
        );
        expect(sent, isEmpty);
      });

      test('fails when the runtime does not answer in time', () async {
        client = build(timeout: const Duration(milliseconds: 20));
        answer = (_) => Completer<http.Response>().future;

        await expectLater(
          client.list(agentId: 'default'),
          throwsA(
            isA<ThreadsException>()
                .having((e) => e.code, 'code', ThreadsErrorCode.requestTimeout)
                .having((e) => e.message, 'message', contains('0s')),
          ),
        );
      });
    });

    group('rename', () {
      test('sends the new name and returns the thread', () async {
        final recorded = threadsExchange('rename');
        reply(200, recorded['body']);

        final thread = await client.rename(
          agentId: 'default',
          threadId: 'a b',
          name: 'Renamed',
        );

        final request = sent.single;
        expect(request.method, 'PATCH');
        expect(
          request.url,
          Uri.parse('http://runtime.test/api/copilotkit/threads/a%20b'),
        );
        expect(request.headers['Content-Type'], contains('application/json'));
        expect(request.headers['Authorization'], 'Bearer token');
        expect(sentBody(), {'agentId': 'default', 'name': 'Renamed'});
        expect(thread, isA<ThreadRecord>());
        expect(thread.id, (recorded['body']! as Map)['id']);
      });

      test('fails when the runtime has no such thread', () async {
        final recorded = threadsExchange('rename-missing');
        reply(recorded['status']! as int, recorded['body']);

        await expectLater(
          client.rename(agentId: 'default', threadId: 'gone', name: 'x'),
          throwsA(
            const ThreadsException(
              code: ThreadsErrorCode.mutationFailed,
              message: 'Failed to update thread',
              statusCode: 500,
            ),
          ),
        );
      });

      test('fails when the answer is not a thread', () async {
        reply(200, '{"id": 1}');

        await expectLater(
          client.rename(agentId: 'default', threadId: 't', name: 'x'),
          throwsA(
            isA<ThreadsException>().having(
              (e) => e.message,
              'message',
              startsWith('The runtime sent invalid thread'),
            ),
          ),
        );
      });
    });

    group('archive', () {
      test('posts to the archive route of the thread', () async {
        reply(200, threadsBody('archive'));

        await client.archive(agentId: 'default', threadId: 't1');

        expect(sent.single.method, 'POST');
        expect(sent.single.url.path, '/api/copilotkit/threads/t1/archive');
        expect(sentBody(), {'agentId': 'default'});
      });

      test('fails when the runtime fails', () async {
        reply(500, {'error': 'Failed to archive thread'});

        await expectLater(
          client.archive(agentId: 'default', threadId: 't1'),
          throwsA(
            isA<ThreadsException>()
                .having((e) => e.code, 'code', ThreadsErrorCode.mutationFailed)
                .having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      });
    });

    group('unarchive', () {
      test('clears archived and returns the thread', () async {
        reply(200, threadsBody('unarchive'));

        final thread = await client.unarchive(
          agentId: 'default',
          threadId: 't1',
        );

        expect(sent.single.method, 'PATCH');
        expect(sent.single.url.path, '/api/copilotkit/threads/t1');
        expect(sentBody(), {'agentId': 'default', 'archived': false});
        expect(thread.archived, isFalse);
      });
    });

    group('delete', () {
      test('sends a DELETE with the agent', () async {
        reply(200, threadsBody('delete'));

        await client.delete(agentId: 'default', threadId: 't1');

        expect(sent.single.method, 'DELETE');
        expect(sent.single.url.path, '/api/copilotkit/threads/t1');
        expect(sentBody(), {'agentId': 'default'});
      });

      test('fails for a thread the runtime no longer has', () async {
        final recorded = threadsExchange('delete-again');
        reply(recorded['status']! as int, recorded['body']);

        await expectLater(
          client.delete(agentId: 'default', threadId: 't1'),
          throwsA(
            isA<ThreadsException>().having(
              (e) => e.message,
              'message',
              'Failed to delete thread',
            ),
          ),
        );
      });
    });

    group('close', () {
      test('closes the client it sends through', () {
        final httpClient = _MockHttpClient();
        when(httpClient.close).thenReturn(null);

        ThreadsClient(
          runtimeUrl: Uri.parse('http://runtime.test'),
          httpClient: httpClient,
        ).close();

        verify(httpClient.close).called(1);
      });

      test('closes the client it created', () {
        ThreadsClient(runtimeUrl: Uri.parse('http://runtime.test')).close();
      });
    });
  });
}
