// cspell:ignore realtime
import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/copilotkit.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

import '../../helpers/memory_fixtures.dart';
import '../../helpers/memory_metadata_fixture.dart';

class _MockHttpClient extends Mock implements http.Client;

class _FakeBaseRequest extends Fake implements http.BaseRequest;

class _MockChannel extends Mock implements PhoenixChannelsClient;

const _newMemory = NewMemory(content: 'Likes tea.', kind: MemoryKind.topical);

void main() {
  setUpAll(() => registerFallbackValue(_FakeBaseRequest()));

  group(MemoriesClient, () {
    late _MockHttpClient httpClient;
    late MemoriesClient client;

    MemoriesClient buildClient({
      Future<Map<String, String>> Function()? headers,
      Duration timeout = const Duration(seconds: 15),
      String url = 'http://runtime.test/api/copilotkit',
    }) => MemoriesClient(
      runtimeUrl: Uri.parse(url),
      headers: headers,
      httpClient: httpClient,
      timeout: timeout,
    );

    setUp(() {
      httpClient = _MockHttpClient();
      client = buildClient();
    });

    void stubResponse(String body, {int status = 200}) {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode(body)), status),
      );
    }

    /// The only request sent so far.
    http.Request sent() =>
        verify(() => httpClient.send(captureAny())).captured.single
            as http.Request;

    group('list', () {
      test('gets the memories and keeps their order', () async {
        stubResponse(memoryFixture('list'));

        final memories = await client.list();

        expect(memories.map((memory) => memory.id), ['mem_2', 'mem_1']);
        final request = sent();
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'http://runtime.test/api/copilotkit/memories',
        );
      });

      test('asks for the retired memories too', () async {
        stubResponse(memoryFixture('list'));

        final memories = await client.list(includeInvalidated: true);

        expect(memories.last.isRetired, isTrue);
        expect(
          sent().url.toString(),
          'http://runtime.test/api/copilotkit/memories?includeInvalidated=true',
        );
      });

      test('ignores trailing slashes of the runtime url', () async {
        client = buildClient(url: 'http://runtime.test/api/copilotkit//');
        stubResponse('{"memories": []}');

        expect(await client.list(), isEmpty);
        expect(
          sent().url.toString(),
          'http://runtime.test/api/copilotkit/memories',
        );
      });

      test('sends the headers of the builder', () async {
        client = buildClient(
          headers: () async => {'Authorization': 'Bearer t'},
        );
        stubResponse('{"memories": []}');

        await client.list();

        expect(sent().headers, {'Authorization': 'Bearer t'});
      });

      for (final status in [403, 404, 422, 501]) {
        test('is unavailable on $status', () {
          stubResponse('', status: status);

          expect(client.list(), throwsA(MemoryUnavailableException(status)));
        });
      }

      test('fails with MEMORY_LIST_FAILED on another status', () {
        stubResponse('', status: 500);

        expect(
          client.list(),
          throwsA(
            const MemoryException(
              code: MemoryErrorCode.listFailed,
              message: 'Request failed: 500',
              statusCode: 500,
            ),
          ),
        );
      });

      for (final (name, body) in [
        ('a body that is not JSON', 'nope'),
        ('a body that is not an object', '[]'),
        ('a body without memories', '{}'),
        ('a memory that is not an object', '{"memories": [1]}'),
        ('a memory that is invalid', '{"memories": [{}]}'),
      ]) {
        test('fails with MEMORY_LIST_FAILED on $name', () {
          stubResponse(body);

          expect(
            client.list(),
            throwsA(
              isA<MemoryException>().having(
                (e) => e.code,
                'code',
                MemoryErrorCode.listFailed,
              ),
            ),
          );
        });
      }

      test('fails with MEMORY_LIST_FAILED when the request throws', () {
        when(() => httpClient.send(any()))
            .thenThrow(http.ClientException('offline'));

        expect(
          client.list(),
          throwsA(
            isA<MemoryException>()
                .having((e) => e.code, 'code', MemoryErrorCode.listFailed)
                .having((e) => e.statusCode, 'statusCode', isNull),
          ),
        );
      });

      test('fails with MEMORY_LIST_FAILED when the headers fail', () {
        client = buildClient(headers: () async => throw StateError('no token'));

        expect(
          client.list(),
          throwsA(
            isA<MemoryException>().having(
              (e) => e.code,
              'code',
              MemoryErrorCode.listFailed,
            ),
          ),
        );
        verifyNever(() => httpClient.send(any()));
      });

      test('fails with MEMORY_REQUEST_TIMEOUT when the runtime is slow', () {
        client = buildClient(timeout: const Duration(milliseconds: 10));
        when(() => httpClient.send(any()))
            .thenAnswer((_) => Completer<http.StreamedResponse>().future);

        expect(
          client.list(),
          throwsA(
            isA<MemoryException>().having(
              (e) => e.code,
              'code',
              MemoryErrorCode.requestTimeout,
            ),
          ),
        );
      });
    });

    group('recall', () {
      test(
        'posts the query with the default limit and keeps the scores',
        () async {
          stubResponse(memoryFixture('recall'));

          final memories = await client.recall('  seats ');

          expect(memories.single.score, 0.87);
          final request = sent();
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://runtime.test/api/copilotkit/memories/recall',
          );
          expect(request.headers['Content-Type'], 'application/json');
          expect(jsonDecode(request.body), {'query': 'seats', 'limit': 5});
        },
      );

      test('sends the limit and the scope', () async {
        stubResponse(memoryFixture('recall'));

        await client.recall('seats', limit: 3, scope: MemoryScope.project);

        expect(jsonDecode(sent().body), {
          'query': 'seats',
          'limit': 3,
          'scope': 'project',
        });
      });

      test('caps the limit at 20', () async {
        stubResponse(memoryFixture('recall'));

        await client.recall('seats', limit: 500);

        expect((jsonDecode(sent().body) as Map)['limit'], 20);
      });

      test('rejects a blank query without sending it', () {
        expect(client.recall('  '), throwsA(isA<MemoryValidationException>()));
        verifyNever(() => httpClient.send(any()));
      });

      test('rejects a limit that is not positive without sending it', () {
        expect(
          client.recall('seats', limit: 0),
          throwsA(isA<MemoryValidationException>()),
        );
        verifyNever(() => httpClient.send(any()));
      });

      test('is unavailable on 404', () {
        stubResponse('', status: 404);

        expect(
          client.recall('seats'),
          throwsA(const MemoryUnavailableException(404)),
        );
      });

      test('fails with MEMORY_RECALL_FAILED on another status', () {
        stubResponse('', status: 502);

        expect(
          client.recall('seats'),
          throwsA(
            isA<MemoryException>().having(
              (e) => e.code,
              'code',
              MemoryErrorCode.recallFailed,
            ),
          ),
        );
      });
    });

    group('save', () {
      test('posts the memory and returns the new one', () async {
        stubResponse(memoryFixture('save_created'), status: 201);

        final outcome = await client.save(
          const NewMemory(
            content: 'Booked a trip to Lima.',
            kind: MemoryKind.episodic,
            sourceThreadIds: ['thread_c'],
          ),
        );

        expect(outcome.memory.id, 'mem_3');
        expect(outcome.isAbsorbed, isFalse);
        expect(outcome.retiredId, isNull);
        final request = sent();
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'http://runtime.test/api/copilotkit/memories',
        );
        expect(jsonDecode(request.body), {
          'content': 'Booked a trip to Lima.',
          'kind': 'episodic',
          'sourceThreadIds': ['thread_c'],
        });
      });

      test('reports a near-duplicate as absorbed', () async {
        stubResponse(memoryFixture('save_absorbed'), status: 201);

        final outcome = await client.save(_newMemory);

        expect(outcome.isAbsorbed, isTrue);
        expect(outcome.memory.id, 'mem_1');
      });

      test('rejects an invalid memory without sending it', () {
        expect(
          client.save(NewMemory(content: 'x' * 8193, kind: MemoryKind.topical)),
          throwsA(isA<MemoryValidationException>()),
        );
        verifyNever(() => httpClient.send(any()));
      });

      test('is unavailable on 404', () {
        stubResponse('', status: 404);

        expect(
          client.save(_newMemory),
          throwsA(const MemoryUnavailableException(404)),
        );
      });

      test('fails with MEMORY_MUTATION_FAILED on another status', () {
        stubResponse('', status: 400);

        final failure = isA<MemoryException>()
            .having((e) => e.code, 'code', MemoryErrorCode.mutationFailed)
            .having((e) => e.isRetryable, 'isRetryable', isFalse);
        expect(client.save(_newMemory), throwsA(failure));
      });

      test('fails with MEMORY_MUTATION_FAILED on an invalid memory', () {
        stubResponse('{"id": "m"}');

        expect(
          client.save(_newMemory),
          throwsA(
            isA<MemoryException>().having(
              (e) => e.code,
              'code',
              MemoryErrorCode.mutationFailed,
            ),
          ),
        );
      });
    });

    group('supersede', () {
      test(
        'patches the memory and returns the new one with the old id',
        () async {
          stubResponse(memoryFixture('supersede'));

          final outcome = await client.supersede(
            'mem 1',
            const NewMemory(
              content: 'Prefers aisle seats.',
              kind: MemoryKind.topical,
            ),
          );

          expect(outcome.memory.id, 'mem_4');
          expect(outcome.retiredId, 'mem_1');
          final request = sent();
          expect(request.method, 'PATCH');
          expect(
            request.url.toString(),
            'http://runtime.test/api/copilotkit/memories/mem%201',
          );
          expect(jsonDecode(request.body), {
            'content': 'Prefers aisle seats.',
            'kind': 'topical',
            'sourceThreadIds': <String>[],
          });
        },
      );

      test('rejects an invalid memory without sending it', () {
        expect(
          client.supersede(
            'mem_1',
            NewMemory(content: 'x' * 8193, kind: MemoryKind.topical),
          ),
          throwsA(isA<MemoryValidationException>()),
        );
        verifyNever(() => httpClient.send(any()));
      });

      test('fails when the answer has no retiredId', () {
        stubResponse(memoryFixture('save_created'));

        expect(
          client.supersede('mem_1', _newMemory),
          throwsA(
            isA<MemoryException>().having(
              (e) => e.code,
              'code',
              MemoryErrorCode.mutationFailed,
            ),
          ),
        );
      });

      test('treats 404 as a missing memory, not as unavailable', () {
        stubResponse('', status: 404);

        expect(
          client.supersede('mem_1', _newMemory),
          throwsA(
            const MemoryException(
              code: MemoryErrorCode.mutationFailed,
              message: 'Request failed: 404',
              statusCode: 404,
            ),
          ),
        );
      });

      test('is unavailable on 403', () {
        stubResponse('', status: 403);

        expect(
          client.supersede('mem_1', _newMemory),
          throwsA(const MemoryUnavailableException(403)),
        );
      });
    });

    group('retire', () {
      test('deletes the memory', () async {
        stubResponse('', status: 204);

        await client.retire('mem_1');

        final request = sent();
        expect(request.method, 'DELETE');
        expect(
          request.url.toString(),
          'http://runtime.test/api/copilotkit/memories/mem_1',
        );
        expect(request.headers, isNot(contains('Content-Type')));
      });

      test('treats 404 as a missing memory, not as unavailable', () {
        stubResponse('', status: 404);

        expect(client.retire('mem_1'), throwsA(isA<MemoryException>()));
      });

      test('is unavailable on 403', () {
        stubResponse('', status: 403);

        expect(
          client.retire('mem_1'),
          throwsA(const MemoryUnavailableException(403)),
        );
      });
    });

    group('subscribe', () {
      test('asks for the credentials of the memory channels', () async {
        stubResponse(jsonEncode(memoryChannelBody('subscribe')));

        final credentials = await client.subscribe();

        final request = sent();
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('http://runtime.test/api/copilotkit/memories/subscribe'),
        );
        expect(request.body, '{}');
        expect(credentials.userTopic, 'user_meta:memories:<join-code>');
      });

      test('fails when the runtime grants no channel', () {
        stubResponse('{"joinCode": "c"}');

        expect(
          client.subscribe(),
          throwsA(
            isA<MemoryException>()
                .having(
                  (e) => e.code,
                  'code',
                  MemoryErrorCode.credentialsFailed,
                )
                .having((e) => e.statusCode, 'statusCode', 200),
          ),
        );
      });

      test('is unavailable on 404', () {
        stubResponse('', status: 404);

        expect(
          client.subscribe(),
          throwsA(const MemoryUnavailableException(404)),
        );
      });
    });

    group('watch', () {
      late Map<String, http.Response> answers;

      setUp(() {
        answers = {
          '/api/copilotkit/info': http.Response(
            jsonEncode({
              'mode': 'intelligence',
              'intelligence': {'wsUrl': 'wss://realtime.test/client'},
            }),
            200,
          ),
          '/api/copilotkit/memories/subscribe': http.Response(
            jsonEncode({'joinToken': 't1', 'joinCode': 'c1'}),
            200,
          ),
        };
        when(() => httpClient.send(any())).thenAnswer((invocation) async {
          final request = invocation.positionalArguments.single as http.Request;
          final answer = answers[request.url.path]!;
          return http.StreamedResponse(
            Stream.value(answer.bodyBytes),
            answer.statusCode,
          );
        });
      });

      test('follows the channel on the runtime real-time socket', () async {
        final channel = _MockChannel();
        final frames = StreamController<PhoenixEvent>.broadcast();
        when(() => channel.events).thenAnswer((_) => frames.stream);
        when(channel.open).thenAnswer((_) async {});
        when(() => channel.join(any(), any())).thenAnswer((_) async => null);
        when(channel.close).thenAnswer((_) => frames.close());
        late Uri socketUrl;
        client = MemoriesClient(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit/'),
          headers: () async => {'Authorization': 'Bearer token'},
          httpClient: httpClient,
          channelFactory: (url, params) {
            socketUrl = url;
            expect(params, {'join_token': 't1'});
            return channel;
          },
        );
        var connected = 0;
        final events = <MemoryMetadataEvent>[];

        final subscription = client
            .watch(onConnected: () => connected++)
            .listen(events.add);
        await pumpEventQueue();
        frames.add(
          PhoenixEvent(
            topic: 'user_meta:memories:c1',
            event: 'memory_metadata',
            payload: memoryMetadataPayload('created'),
          ),
        );
        await pumpEventQueue();

        expect(socketUrl, Uri.parse('wss://realtime.test/client'));
        verify(() => channel.join('user_meta:memories:c1', {})).called(1);
        expect(connected, 1);
        expect(events.single.operation, MemoryMetadataOperation.created);
        final requests = verify(() => httpClient.send(captureAny())).captured
            .cast<http.Request>();
        expect(
          requests.map((request) => request.headers['Authorization']),
          everyElement('Bearer token'),
        );
        await subscription.cancel();
      });

      test('fails when the runtime has no real-time service', () async {
        for (final info in [
          {'mode': 'sse'},
          {
            'mode': 'intelligence',
            'intelligence': {'wsUrl': ''},
          },
        ]) {
          answers['/api/copilotkit/info'] = http.Response(
            jsonEncode(info),
            200,
          );

          await expectLater(
            client.watch(),
            emitsError(
              isA<MemoryException>().having(
                (e) => e.code,
                'code',
                MemoryErrorCode.realtimeUnavailable,
              ),
            ),
          );
        }
      });

      test('fails when the runtime info cannot be read', () async {
        answers['/api/copilotkit/info'] = http.Response('', 404);

        await expectLater(
          client.watch(),
          emitsError(
            isA<MemoryException>()
                .having(
                  (e) => e.code,
                  'code',
                  MemoryErrorCode.realtimeUnavailable,
                )
                .having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      });
    });

    test('closes the http client', () {
      when(() => httpClient.close()).thenReturn(null);

      client.close();

      verify(() => httpClient.close()).called(1);
    });

    test('creates its own http client by default', () {
      MemoriesClient(runtimeUrl: Uri.parse('http://runtime.test')).close();
    });
  });
}
