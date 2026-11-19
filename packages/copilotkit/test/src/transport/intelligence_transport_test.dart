// cspell:ignore realtime
import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/intelligence_transport.dart';
import 'package:copilotkit/src/transport/models/runtime_mode.dart';
import 'package:copilotkit/src/transport/models/thread_locked_exception.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

import '../../helpers/agent.dart';
import '../../helpers/fixtures.dart';

class _MockHttpClient extends Mock implements http.Client;

class _MockChannel extends Mock implements PhoenixChannelsClient;

class _FakeBaseRequest extends Fake implements http.BaseRequest;

const _input = RunAgentInput(
  threadId: 'thread-1',
  runId: 'run-1',
  messages: [],
  tools: [],
  context: [],
);

const Map<String, Object?> _credentials = {
  'threadId': 'server-thread',
  'runId': 'server-run',
  'joinToken': 'token-1',
  'realtime': {
    'clientUrl': 'wss://realtime.test/client',
    'topic': 'thread:server-thread',
  },
};

PhoenixEvent _frame(String event, Map<String, Object?> payload) =>
    PhoenixEvent(topic: 'thread:server-thread', event: event, payload: payload);

PhoenixEvent _agUi(Map<String, Object?> event) => _frame('ag_ui_event', event);

PhoenixEvent _started() =>
    _agUi({'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'});

PhoenixEvent _finished() =>
    _agUi({'type': 'RUN_FINISHED', 'threadId': 't', 'runId': 'r'});

void main() {
  setUpAll(() => registerFallbackValue(_FakeBaseRequest()));

  group(IntelligenceTransport, () {
    late _MockHttpClient httpClient;
    late _MockChannel channel;
    late StreamController<PhoenixEvent> frames;
    late Uri joinedUrl;
    late Map<String, String> joinedParams;
    late IntelligenceTransport transport;
    late List<Object> skipped;

    IntelligenceTransport build({
      Duration stopTimeout = const Duration(seconds: 10),
      void Function(Object, StackTrace)? onSkippedEvent,
      Uri? runtimeUrl,
      int maxReconnects = 5,
    }) => IntelligenceTransport(
      runtimeUrl: runtimeUrl ?? Uri.parse('http://runtime.test/api/copilotkit'),
      httpClientFactory: () => httpClient,
      channelFactory: (url, params) {
        joinedUrl = url;
        joinedParams = params;
        return channel;
      },
      stopTimeout: stopTimeout,
      maxReconnects: maxReconnects,
      reconnectDelay: (_) => Duration.zero,
      onSkippedEvent: onSkippedEvent ?? (error, _) => skipped.add(error),
    );

    void stubHttp(int status, Object body) {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(body is String ? body : jsonEncode(body))),
          status,
        ),
      );
    }

    http.Request sentRequest() =>
        verify(() => httpClient.send(captureAny())).captured.last
            as http.Request;

    setUp(() {
      httpClient = _MockHttpClient();
      channel = _MockChannel();
      frames = StreamController<PhoenixEvent>.broadcast();
      skipped = [];
      when(() => channel.events).thenAnswer((_) => frames.stream);
      when(channel.open).thenAnswer((_) async {});
      when(() => channel.join(any(), any())).thenAnswer((_) async => {});
      when(channel.close).thenAnswer((_) async {});
      stubHttp(200, _credentials);
      transport = build();
    });

    tearDown(() async {
      await transport.close();
      await frames.close();
    });

    group('connect', () {
      const connectCredentials = <String, Object?>{
        'threadId': 'server-thread',
        'joinToken': 'token-1',
        'realtime': {
          'clientUrl': 'wss://realtime.test/client',
          'topic': 'thread:server-thread',
        },
      };

      PhoenixEvent started(String runId) => _agUi({
        'type': 'RUN_STARTED',
        'threadId': 'server-thread',
        'runId': runId,
      });

      PhoenixEvent finished(String runId) => _agUi({
        'type': 'RUN_FINISHED',
        'threadId': 'server-thread',
        'runId': runId,
      });

      PhoenixEvent text(String delta) => _agUi({
        'type': 'TEXT_MESSAGE_CONTENT',
        'messageId': 'm1',
        'delta': delta,
      });

      PhoenixEvent replayComplete() =>
          _frame('replay_complete', {'latestEventId': null});

      PhoenixEvent streamIdle() => _frame('stream_idle', {});

      Future<List<BaseEvent>> replay(
        List<PhoenixEvent> sent, {
        Map<String, String> headers = const {},
      }) async {
        final events = transport
            .connect(agentId: 'a', input: _input, headers: headers)
            .toList();
        await pumpEventQueue();
        sent.forEach(frames.add);
        return await events;
      }

      setUp(() => stubHttp(200, connectCredentials));

      test('asks the runtime for a full replay of the thread', () async {
        final events = await replay(
          [replayComplete(), streamIdle()],
          headers: {'Authorization': 'Bearer token'},
        );

        final request = sentRequest();
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('http://runtime.test/api/copilotkit/agent/a/connect'),
        );
        expect(request.headers['Authorization'], 'Bearer token');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['threadId'], 'thread-1');
        expect(body, containsPair('lastSeenEventId', null));
        expect(events, isEmpty);
      });

      test('turns a recorded replay into events', () async {
        final rows = loadFixture('intelligence_connect_replay').rawEvents;
        stubHttp(200, rows.firstWhere((row) => row['kind'] == 'http')['body']!);

        final events = await replay([
          for (final row in rows)
            if (row['kind'] == 'frame')
              _frame(
                row['event']! as String,
                row['payload']! as Map<String, Object?>,
              ),
        ]);

        // The recording lacks the end of the run, and it stays so.
        expect(events, [
          isA<RunStartedEvent>(),
          isA<TextMessageStartEvent>(),
          isA<TextMessageContentEvent>(),
        ]);
        expect(
          (events.first as RunStartedEvent).input?.messages.single.id,
          'u1',
        );
        expect(skipped, isEmpty);
      });

      test('joins in connect mode with no cursor', () async {
        await replay([replayComplete(), streamIdle()]);

        expect(joinedUrl, Uri.parse('wss://realtime.test/client'));
        expect(joinedParams, {'join_token': 'token-1'});
        verifyInOrder([
          channel.open,
          () => channel.join('thread:server-thread', const {
            'stream_mode': 'connect',
            'last_seen_event_id': null,
          }),
        ]);
      });

      test('streams the replayed events and ends when it is idle', () async {
        final events = await replay([
          _frame('connected', {}),
          started('r1'),
          text('Hello'),
          finished('r1'),
          replayComplete(),
          streamIdle(),
        ]);

        expect(events, [
          isA<RunStartedEvent>(),
          isA<TextMessageContentEvent>(),
          isA<RunFinishedEvent>(),
        ]);
        verify(channel.close).called(1);
      });

      test('keeps streaming after a RUN_FINISHED until it is idle', () async {
        final events = await replay([
          started('r1'),
          finished('r1'),
          replayComplete(),
          started('r2'),
          text('Live'),
          finished('r2'),
          streamIdle(),
        ]);

        expect(events, hasLength(5));
      });

      test('does not end on stream_idle alone', () async {
        final received = <BaseEvent>[];
        var done = false;
        transport
            .connect(agentId: 'a', input: _input)
            .listen(received.add, onDone: () => done = true);
        await pumpEventQueue();

        frames.add(streamIdle());
        await pumpEventQueue();
        expect(done, isFalse);

        frames
          ..add(text('late'))
          ..add(replayComplete());
        await pumpEventQueue();
        expect(done, isTrue);
        expect(received, [isA<TextMessageContentEvent>()]);
      });

      test('passes on a run the replay left open as it is', () async {
        final events = await replay([
          started('r1'),
          text('Hello'),
          replayComplete(),
          streamIdle(),
        ]);

        expect(events, [
          isA<RunStartedEvent>(),
          isA<TextMessageContentEvent>(),
        ]);
      });

      group('when the gateway is quiet', () {
        // The transport the test tears down, so none outlives it.
        IntelligenceTransport quick() => transport = IntelligenceTransport(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
          httpClientFactory: () => httpClient,
          channelFactory: (_, _) => channel,
          idleFallback: const Duration(milliseconds: 20),
          idleWarning: const Duration(milliseconds: 40),
        );

        Future<bool> endsWithin(
          IntelligenceTransport transport,
          List<PhoenixEvent> sent,
        ) async {
          var done = false;
          transport
              .connect(agentId: 'a', input: _input)
              .listen((_) {}, onDone: () => done = true);
          await pumpEventQueue();
          sent.forEach(frames.add);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return done;
        }

        test(
          'ends on a stream_idle that names no event, without replay_complete',
          () async {
            expect(await endsWithin(quick(), [streamIdle()]), isTrue);
          },
        );

        test(
          'ends on a stream_idle that names the last event it saw',
          () async {
            final seen = _agUi({
              'type': 'TEXT_MESSAGE_CONTENT',
              'messageId': 'm1',
              'delta': 'x',
              'metadata': {'cpki_event_id': 'e1'},
            });

            expect(
              await endsWithin(quick(), [
                seen,
                _frame('stream_idle', {'latestEventId': 'e1'}),
              ]),
              isTrue,
            );
          },
        );

        test(
          'keeps going on a stream_idle that belongs to other events',
          () async {
            expect(
              await endsWithin(quick(), [
                _frame('stream_idle', {'latestEventId': 'someone-else'}),
              ]),
              isFalse,
            );
          },
        );

        test(
          'does not end on a stream_idle when replay_complete follows',
          () async {
            expect(
              await endsWithin(quick(), [streamIdle(), replayComplete()]),
              isTrue,
            );
          },
        );

        test('keeps the stream open after replay_complete and warns', () async {
          final done = await endsWithin(quick(), [replayComplete()]);

          expect(done, isFalse);
        });

        test('does not resume from an event that is not stored yet', () async {
          final ingested = _agUi({
            'type': 'TEXT_MESSAGE_CONTENT',
            'messageId': 'm1',
            'delta': 'x',
            'metadata': {'cpki_event_id': 'cpki_ingested_1'},
          });
          final events = quick().connect(agentId: 'a', input: _input).toList();
          await pumpEventQueue();
          frames.add(ingested);
          await pumpEventQueue();
          await frames.close();
          await Future<void>.delayed(const Duration(milliseconds: 50));

          // The second request carried no cursor.
          final bodies = verify(() => httpClient.send(captureAny())).captured
              .cast<http.Request>()
              .map((r) => jsonDecode(r.body) as Map<String, Object?>)
              .toList();
          expect(bodies.first, containsPair('lastSeenEventId', null));
          await events.timeout(
            const Duration(milliseconds: 1),
            onTimeout: () => <BaseEvent>[],
          );
        });
      });

      group('when the channel drops', () {
        late List<StreamController<PhoenixEvent>> attempts;
        late int channelsMade;

        PhoenixEvent withId(String id) => _agUi({
          'type': 'TEXT_MESSAGE_CONTENT',
          'messageId': 'm1',
          'delta': id,
          'metadata': {'cpki_event_id': id},
        });

        IntelligenceTransport reconnecting({int maxReconnects = 5}) =>
            IntelligenceTransport(
              runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
              httpClientFactory: () => httpClient,
              channelFactory: (_, _) {
                channelsMade++;
                return channel;
              },
              maxReconnects: maxReconnects,
              reconnectDelay: (_) => Duration.zero,
              onSkippedEvent: (error, _) => skipped.add(error),
            );

        setUp(() {
          channelsMade = 0;
          attempts = List.generate(
            3,
            (_) => StreamController<PhoenixEvent>.broadcast(),
          );
          var next = 0;
          when(() => channel.events).thenAnswer((_) => attempts[next++].stream);
          // Connect replies are fresh for each attempt.
          stubHttp(200, connectCredentials);
        });

        tearDown(() async {
          for (final attempt in attempts) {
            await attempt.close();
          }
        });

        Map<String, Object?> sentBody(int index) => jsonDecode(
          (verify(() => httpClient.send(captureAny())).captured[index]
                  as http.Request)
              .body,
        ) as Map<String, Object?>;

        test('replays again from the last event it saw', () async {
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          attempts[0].add(withId('e1'));
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          attempts[1]
            ..add(withId('e2'))
            ..add(replayComplete())
            ..add(streamIdle());

          expect(await events, [
            isA<TextMessageContentEvent>(),
            isA<TextMessageContentEvent>(),
          ]);
          expect(channelsMade, 2);
          expect(sentBody(1), containsPair('lastSeenEventId', 'e1'));
          verify(
            () => channel.join('thread:server-thread', const {
              'stream_mode': 'connect',
              'last_seen_event_id': 'e1',
            }),
          ).called(1);
        });

        test('replays in full when no event was seen yet', () async {
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());

          expect(await events, isEmpty);
          expect(sentBody(1), containsPair('lastSeenEventId', null));
        });

        test('replays again after a channel error', () async {
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          attempts[0].addError(StateError('socket'));
          await pumpEventQueue();
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());

          expect(await events, isEmpty);
          expect(channelsMade, 2);
        });

        /// Answers the connect requests in turn: a status code, or an error to
        /// throw.
        void answerInTurn(List<Object> steps) {
          var next = 0;
          when(() => httpClient.send(any())).thenAnswer((_) async {
            final step = steps[next++];
            if (step is int) {
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    step == 200 ? jsonEncode(connectCredentials) : 'no',
                  ),
                ),
                step,
              );
            }
            throw step as Exception;
          });
        }

        Future<List<BaseEvent>> dropOnceThenFinish(
          IntelligenceTransport reconnecting,
        ) async {
          final events = reconnecting
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());
          attempts[2]
            ..add(replayComplete())
            ..add(streamIdle());
          return await events;
        }

        test('keeps trying while the network is still down', () async {
          answerInTurn([200, http.ClientException('offline'), 200]);
          transport = reconnecting();

          expect(await dropOnceThenFinish(transport), isEmpty);

          verify(() => httpClient.send(any())).called(3);
          expect(channelsMade, 2);
        });

        test('treats a 5xx while reconnecting as another drop', () async {
          answerInTurn([200, 503, 200]);
          transport = reconnecting();

          expect(await dropOnceThenFinish(transport), isEmpty);

          verify(() => httpClient.send(any())).called(3);
        });

        test(
          'treats a rate limit while reconnecting as another drop',
          () async {
            answerInTurn([200, 429, 200]);
            transport = reconnecting();

            expect(await dropOnceThenFinish(transport), isEmpty);
          },
        );

        test('fails at once when a reconnect is refused', () async {
          answerInTurn([200, 401]);
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          await attempts[0].close();

          await expectLater(
            events,
            throwsA(
              isA<http.ClientException>().having(
                (e) => e.message,
                'message',
                contains('status 401'),
              ),
            ),
          );
        });

        test(
          'treats a socket that closes while reconnecting as a drop',
          () async {
            var joins = 0;
            when(() => channel.join(any(), any())).thenAnswer((_) async {
              if (joins++ == 1) throw const PhoenixClosedException();
              return {};
            });
            transport = reconnecting();

            expect(await dropOnceThenFinish(transport), isEmpty);

            expect(channelsMade, 3);
          },
        );

        test('fails when a reconnect is refused at the join', () async {
          var joins = 0;
          when(() => channel.join(any(), any())).thenAnswer((_) async {
            if (joins++ == 1) {
              throw const PhoenixReplyException(
                status: 'error',
                response: 'unauthorized',
              );
            }
            return {};
          });
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          await attempts[0].close();

          await expectLater(events, throwsA(isA<PhoenixReplyException>()));
        });

        test('treats a drop during the join as a drop, not a hang', () async {
          var joins = 0;
          final neverAnswers = Completer<Map<String, Object?>>();
          when(() => channel.join(any(), any())).thenAnswer((_) {
            if (joins++ == 0) return neverAnswers.future;
            return Future.value(<String, Object?>{});
          });
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          // The socket drops while the join is still waiting for its answer.
          await attempts[0].close();
          await pumpEventQueue();
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());

          expect(await events, isEmpty);
          expect(channelsMade, 2);
        });

        test('keeps a pause across a reconnect', () async {
          transport = IntelligenceTransport(
            runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
            httpClientFactory: () => httpClient,
            channelFactory: (_, _) => channel,
            reconnectDelay: (_) => const Duration(milliseconds: 50),
          );
          final received = <BaseEvent>[];
          final subscription = transport
              .connect(agentId: 'a', input: _input)
              .listen(received.add);
          await pumpEventQueue();
          await attempts[0].close();
          subscription.pause();
          await Future<void>.delayed(const Duration(milliseconds: 150));
          attempts[1].add(withId('e2'));
          await pumpEventQueue();

          expect(received, isEmpty);
          subscription.resume();
          await pumpEventQueue();
          expect(received, [isA<TextMessageContentEvent>()]);
          await subscription.cancel();
        });

        test('moves the cursor past an event it skipped', () async {
          transport = reconnecting();
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          attempts[0].add(
            _agUi({
              'type': 'NOT_AN_EVENT',
              'metadata': {'cpki_event_id': 'e9'},
            }),
          );
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());
          await events;

          expect(sentBody(1), containsPair('lastSeenEventId', 'e9'));
          expect(skipped, hasLength(1));
        });

        test(
          'starts the count over after an attempt that made progress',
          () async {
            transport = reconnecting(maxReconnects: 1);
            final events = transport
                .connect(agentId: 'a', input: _input)
                .toList();
            await pumpEventQueue();
            attempts[0].add(withId('e1'));
            await pumpEventQueue();
            await attempts[0].close();
            await pumpEventQueue();
            attempts[1].add(withId('e2'));
            await pumpEventQueue();
            await attempts[1].close();
            await pumpEventQueue();
            attempts[2]
              ..add(replayComplete())
              ..add(streamIdle());

            // Two drops in a row would exceed one reconnect, but each attempt
            // delivered an event.
            expect(await events, hasLength(2));
            expect(channelsMade, 3);
          },
        );

        test('gives up after the limit and reports the drop', () async {
          transport = reconnecting(maxReconnects: 1);
          final done = expectLater(
            transport.connect(agentId: 'a', input: _input),
            emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
          );
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          await attempts[1].close();
          await done;

          expect(channelsMade, 2);
        });

        test('waits a little by default before replaying again', () async {
          transport = IntelligenceTransport(
            runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
            httpClientFactory: () => httpClient,
            channelFactory: (_, _) {
              channelsMade++;
              return channel;
            },
          );
          final events = transport
              .connect(agentId: 'a', input: _input)
              .toList();
          await pumpEventQueue();
          await attempts[0].close();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          attempts[1]
            ..add(replayComplete())
            ..add(streamIdle());

          expect(await events, isEmpty);
          expect(channelsMade, 2);
        });

        test('stops waiting to reconnect when it is cancelled', () async {
          transport = IntelligenceTransport(
            runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
            httpClientFactory: () => httpClient,
            channelFactory: (_, _) {
              channelsMade++;
              return channel;
            },
            reconnectDelay: (_) => const Duration(milliseconds: 50),
          );
          final subscription = transport
              .connect(agentId: 'a', input: _input)
              .listen((_) {});
          await pumpEventQueue();
          await attempts[0].close();
          await pumpEventQueue();
          await subscription.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 120));

          expect(channelsMade, 1);
        });
      });

      test('skips an event it cannot decode and reports it', () async {
        final events = await replay([
          _agUi({'type': 'NOT_AN_EVENT'}),
          replayComplete(),
          streamIdle(),
        ]);

        expect(events, isEmpty);
        expect(skipped, hasLength(1));
      });

      test('is empty when the runtime has no history', () async {
        stubHttp(204, '');

        expect(
          await transport.connect(agentId: 'a', input: _input).toList(),
          isEmpty,
        );
        verifyNever(channel.open);
        verifyNever(() => channel.join(any(), any()));
      });

      test('fails when the runtime rejects the request', () async {
        stubHttp(500, 'down');

        await expectLater(
          transport.connect(agentId: 'a', input: _input).toList(),
          throwsA(
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              contains('Connect failed with status 500'),
            ),
          ),
        );
      });

      test('fails when the answer is not a JSON object', () async {
        stubHttp(200, '[]');

        await expectLater(
          transport.connect(agentId: 'a', input: _input).toList(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('connect credentials'),
            ),
          ),
        );
      });

      test('fails when the answer lacks a field', () async {
        stubHttp(200, {'threadId': 't'});

        await expectLater(
          transport.connect(agentId: 'a', input: _input).toList(),
          throwsA(isA<FormatException>()),
        );
      });

      test('fails when the join is refused', () async {
        when(() => channel.join(any(), any())).thenThrow(
          const PhoenixReplyException(
            status: 'error',
            response: 'unauthorized',
          ),
        );

        await expectLater(
          transport.connect(agentId: 'a', input: _input).toList(),
          throwsA(isA<PhoenixReplyException>()),
        );
        verify(channel.close).called(1);
      });

      test('fails when the channel closes before the replay ends', () async {
        transport = build(maxReconnects: 0);
        final events = transport.connect(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        await frames.close();

        await expectLater(
          events,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('before the replay finished'),
            ),
          ),
        );
      });

      test('fails with the error that dropped the connection', () async {
        transport = build(maxReconnects: 0);
        final events = transport.connect(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames.addError(const PhoenixClosedException());

        await expectLater(events, throwsA(isA<PhoenixClosedException>()));
        verify(channel.close).called(1);
      });

      test('closes the channel when cancelled', () async {
        final subscription = transport
            .connect(agentId: 'a', input: _input)
            .listen((_) {});
        await pumpEventQueue();

        await subscription.cancel();
        await pumpEventQueue();

        verify(channel.close).called(1);
      });

      test(
        'does not join when cancelled before the runtime answered',
        () async {
          final answer = Completer<http.StreamedResponse>();
          when(() => httpClient.send(any())).thenAnswer((_) => answer.future);
          final subscription = transport
              .connect(agentId: 'a', input: _input)
              .listen((_) {});
          await pumpEventQueue();

          await subscription.cancel();
          answer.complete(
            http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(connectCredentials))),
              200,
            ),
          );
          await pumpEventQueue();

          verifyNever(() => channel.join(any(), any()));
        },
      );

      test('sends nothing when the transport closes first', () async {
        final events = transport.connect(agentId: 'a', input: _input);

        await transport.close();

        expect(await events.toList(), isEmpty);
        verifyNever(() => httpClient.send(any()));
      });

      test('pauses and resumes the channel with the subscription', () async {
        final received = <BaseEvent>[];
        final subscription = transport
            .connect(agentId: 'a', input: _input)
            .listen(received.add);
        await pumpEventQueue();

        subscription.pause();
        frames.add(text('held'));
        await pumpEventQueue();
        expect(received, isEmpty);

        subscription.resume();
        await pumpEventQueue();
        expect(received, [isA<TextMessageContentEvent>()]);
        await subscription.cancel();
      });
    });

    group('run', () {
      test('asks the runtime to start the run', () async {
        final events = transport
            .run(
              agentId: 'my agent',
              input: _input,
              headers: {'Authorization': 'Bearer token'},
            )
            .toList();
        await pumpEventQueue();

        final request = sentRequest();
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('http://runtime.test/api/copilotkit/agent/my%20agent/run'),
        );
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['threadId'], 'thread-1');
        expect(body['runId'], 'run-1');
        expect(body['messages'], isEmpty);
        expect(body['state'], isNotNull);
        frames.add(_finished());
        await events;
      });

      test('ignores a trailing slash in the runtime url', () async {
        transport = build(runtimeUrl: Uri.parse('http://runtime.test/api/'));

        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        expect(sentRequest().url.path, '/api/agent/a/run');
        frames.add(_finished());
        await events;
      });

      test('joins the topic of the credentials with the join token', () async {
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        expect(joinedUrl, Uri.parse('wss://realtime.test/client'));
        expect(joinedParams, {'join_token': 'token-1'});
        verifyInOrder([
          channel.open,
          () => channel.join('thread:server-thread', const {}),
        ]);
        frames.add(_finished());
        await events;
      });

      test(
        'streams the events of the channel and ends on RUN_FINISHED',
        () async {
          final events = transport.run(agentId: 'a', input: _input);

          final expectation = expectLater(
            events,
            emitsInOrder([
              isA<RunStartedEvent>(),
              isA<TextMessageStartEvent>(),
              isA<RunFinishedEvent>(),
              emitsDone,
            ]),
          );
          await pumpEventQueue();
          frames
            ..add(_frame('connected', {'thread_id': 't'}))
            ..add(_started())
            ..add(_frame('replay_complete', {'thread_id': 't'}))
            ..add(
              _agUi({
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'm',
                'role': 'assistant',
              }),
            )
            ..add(_finished());
          await expectation;
        },
      );

      test('ends on RUN_ERROR and keeps the error', () async {
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames.add(
          _agUi({'type': 'RUN_ERROR', 'message': 'boom', 'code': 'X'}),
        );

        final received = await events;
        expect(received.single, isA<RunErrorEvent>());
        verify(channel.close).called(1);
      });

      test('closes the channel when the run finishes', () async {
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames.add(_finished());
        await events;

        verify(channel.close).called(1);
      });

      test(
        'skips an event it cannot decode and tells onSkippedEvent',
        () async {
          final events = transport.run(agentId: 'a', input: _input).toList();
          await pumpEventQueue();

          frames
            ..add(_agUi({'type': 'SOMETHING_NEW'}))
            ..add(_agUi({'type': 'TEXT_MESSAGE_START'}))
            ..add(_finished());

          expect(await events, [isA<RunFinishedEvent>()]);
          expect(skipped, hasLength(2));
        },
      );

      test('keeps running when onSkippedEvent throws', () async {
        transport = build(
          onSkippedEvent: (error, stackTrace) => throw StateError('app bug'),
        );
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames
          ..add(_agUi({'type': 'SOMETHING_NEW'}))
          ..add(_finished());

        expect(await events, [isA<RunFinishedEvent>()]);
      });

      test('skips an event without a callback', () async {
        transport = IntelligenceTransport(
          runtimeUrl: Uri.parse('http://runtime.test'),
          httpClientFactory: () => httpClient,
          channelFactory: (_, _) => channel,
        );
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames
          ..add(_agUi({'type': 'SOMETHING_NEW'}))
          ..add(_finished());

        expect(await events, [isA<RunFinishedEvent>()]);
      });

      test('cancelling closes the channel', () async {
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen((_) {});
        await pumpEventQueue();

        await subscription.cancel();

        verify(channel.close).called(1);
        expect(frames.hasListener, isFalse);
      });

      test('pausing holds the events until it resumes', () async {
        final received = <BaseEvent>[];
        final subscription = transport
            .run(agentId: 'a', input: _input)
            .listen(received.add);
        await pumpEventQueue();

        subscription.pause();
        frames.add(_started());
        await pumpEventQueue();
        expect(received, isEmpty);

        subscription.resume();
        await pumpEventQueue();
        expect(received, [isA<RunStartedEvent>()]);
        await subscription.cancel();
      });

      test(
        'does not join when cancelled before the runtime answered',
        () async {
          final answer = Completer<http.StreamedResponse>();
          when(() => httpClient.send(any())).thenAnswer((_) => answer.future);
          final subscription = transport
              .run(agentId: 'a', input: _input)
              .listen((_) {});
          await pumpEventQueue();

          await subscription.cancel();
          answer.complete(
            http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(_credentials))),
              200,
            ),
          );
          await pumpEventQueue();

          verifyNever(() => channel.join(any(), any()));
        },
      );

      test(
        'sends nothing when the transport closes before it listens',
        () async {
          final events = transport.run(agentId: 'a', input: _input);

          await transport.close();

          expect(await events.toList(), isEmpty);
          verifyNever(() => httpClient.send(any()));
        },
      );

      test(
        'fails with ThreadLockedException when the thread is busy',
        () async {
          stubHttp(409, {'error': 'Thread lock denied'});

          await expectLater(
            transport.run(agentId: 'a', input: _input),
            emitsInOrder([
              emitsError(
                const ThreadLockedException(message: 'Thread lock denied'),
              ),
              emitsDone,
            ]),
          );
          verifyNever(() => channel.open());
        },
      );

      test(
        'fails with ThreadLockedException when 409 has no message',
        () async {
          stubHttp(409, 'not json');

          await expectLater(
            transport.run(agentId: 'a', input: _input),
            emitsInOrder([
              emitsError(const ThreadLockedException()),
              emitsDone,
            ]),
          );
        },
      );

      test('fails with ThreadLockedException when 409 has no error', () async {
        stubHttp(409, {'detail': 'busy'});

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(const ThreadLockedException()), emitsDone]),
        );
      });

      test('fails with a ClientException on another status', () async {
        stubHttp(500, 'oops');

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([
            emitsError(
              isA<http.ClientException>().having(
                (e) => e.message,
                'message',
                contains('Run failed with status 500: oops'),
              ),
            ),
            emitsDone,
          ]),
        );
      });

      for (final entry in {
        'JSON that is not an object': '[1]',
        'invalid JSON': '{nope',
        'credentials without a join token': jsonEncode({
          'threadId': 't',
          'runId': 'r',
          'realtime': {'clientUrl': 'wss://x', 'topic': 't'},
        }),
      }.entries) {
        test('fails with a FormatException on ${entry.key}', () async {
          stubHttp(200, entry.value);

          await expectLater(
            transport.run(agentId: 'a', input: _input),
            emitsInOrder([emitsError(isA<FormatException>()), emitsDone]),
          );
          verifyNever(() => channel.open());
        });
      }

      test('fails when the socket does not open', () async {
        when(channel.open).thenAnswer((_) async => throw StateError('refused'));

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<StateError>()), emitsDone]),
        );
        verify(channel.close).called(1);
      });

      test('fails when the join is refused', () async {
        when(() => channel.join(any(), any())).thenAnswer(
          (_) async =>
              throw const PhoenixReplyException(status: 'error', response: {}),
        );

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<PhoenixReplyException>()), emitsDone]),
        );
      });

      test('fails with the error that dropped the connection', () async {
        final events = transport.run(agentId: 'a', input: _input);
        final expectation = expectLater(
          events,
          emitsInOrder([
            isA<RunStartedEvent>(),
            emitsError(const PhoenixClosedException(code: 1006)),
            emitsDone,
          ]),
        );
        await pumpEventQueue();

        frames
          ..add(_started())
          ..addError(const PhoenixClosedException(code: 1006));

        await expectation;
      });

      test('ends when the channel ends without an error', () async {
        final events = transport.run(agentId: 'a', input: _input);
        final expectation = expectLater(events, emitsDone);
        await pumpEventQueue();

        await frames.close();

        await expectation;
      });

      test('does not fail when closing the channel throws', () async {
        when(channel.close).thenAnswer((_) async => throw StateError('gone'));
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        frames.add(_finished());

        expect(await events, [isA<RunFinishedEvent>()]);
      });

      test('connects to the real socket by default', () async {
        stubHttp(200, {
          ..._credentials,
          'realtime': {
            'clientUrl': 'ws://127.0.0.1:1/client',
            'topic': 'thread:t',
          },
        });
        transport = IntelligenceTransport(
          runtimeUrl: Uri.parse('http://runtime.test'),
          httpClientFactory: () => httpClient,
        );

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<Exception>()), emitsDone]),
        );
      });

      test('fails with the http client error when the POST fails', () async {
        when(() => httpClient.send(any()))
            .thenThrow(http.ClientException('offline'));

        await expectLater(
          transport.run(agentId: 'a', input: _input),
          emitsInOrder([emitsError(isA<http.ClientException>()), emitsDone]),
        );
      });
    });

    group('replaying the recorded runs', () {
      Future<List<BaseEvent>> replay(String name) async {
        final rows = loadFixture(name).rawEvents;
        final run = rows.firstWhere((row) => row['step'] == 'run');
        stubHttp(run['status']! as int, run['body']!);
        final received = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();
        for (final row in rows.where((row) => row['kind'] == 'frame')) {
          frames.add(
            _frame(
              row['event']! as String,
              row['payload']! as Map<String, Object?>,
            ),
          );
        }
        return await received;
      }

      test('a text reply ends with the text the runtime streamed', () async {
        final events = await replay('intelligence_text_run');

        expect(events.first, isA<RunStartedEvent>());
        expect(events.last, isA<RunFinishedEvent>());
        final streamed = loadFixture('intelligence_text_run').rawEvents
            .where((row) => row['event'] == 'ag_ui_event')
            .map((row) => row['payload']! as Map<String, Object?>)
            .where((payload) => payload['type'] == 'TEXT_MESSAGE_CONTENT')
            .map((payload) => payload['delta']! as String)
            .join();
        final state = mapEvents(events).state;
        expect(state.messages.last.text, streamed);
        expect(state.error, isNull);
      });

      test('a tool run ends with the tool call the runtime made', () async {
        final events = await replay('intelligence_tool_run');

        expect(events.last, isA<RunFinishedEvent>());
        final call = events.whereType<ToolCallStartEvent>().single;
        expect(call.toolCallName, 'showWeather');
        final args = events.whereType<ToolCallArgsEvent>().map((e) => e.delta);
        expect(jsonDecode(args.join()), {'city': 'Lima'});
      });
    });

    group('stop', () {
      test('posts the run id to the stop route of the thread', () async {
        stubHttp(200, {'stopped': true});

        await transport.stop(
          agentId: 'my agent',
          threadId: 'thread 1',
          runId: 'run-1',
          headers: {'Authorization': 'Bearer token'},
        );

        final request = sentRequest();
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse(
            'http://runtime.test/api/copilotkit/agent/my%20agent/stop/thread%201',
          ),
        );
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {'runId': 'run-1'});
      });

      test('uses the ids the runtime gave the run', () async {
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();
        frames.add(_finished());
        await events;
        stubHttp(200, {'stopped': true});

        await transport.stop(
          agentId: 'a',
          threadId: 'thread-1',
          runId: 'run-1',
        );

        final request = sentRequest();
        expect(request.url.path, endsWith('/agent/a/stop/server-thread'));
        expect(jsonDecode(request.body), {'runId': 'server-run'});
      });

      test('throws ThreadLockedException on 409', () async {
        stubHttp(409, {'error': 'Thread lock denied'});

        await expectLater(
          transport.stop(agentId: 'a', threadId: 't', runId: 'r'),
          throwsA(const ThreadLockedException(message: 'Thread lock denied')),
        );
      });

      test('throws a ClientException on another status', () async {
        stubHttp(500, 'oops');

        await expectLater(
          transport.stop(agentId: 'a', threadId: 't', runId: 'r'),
          throwsA(
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              contains('Stop failed with status 500: oops'),
            ),
          ),
        );
      });

      test(
        'throws a ClientException when the runtime does not answer',
        () async {
          transport = build(stopTimeout: const Duration(milliseconds: 10));
          when(() => httpClient.send(any()))
              .thenAnswer((_) => Completer<http.StreamedResponse>().future);

          await expectLater(
            transport.stop(agentId: 'a', threadId: 't', runId: 'r'),
            throwsA(
              isA<http.ClientException>().having(
                (e) => e.message,
                'message',
                contains('timed out after 10ms'),
              ),
            ),
          );
        },
      );
    });

    group('info', () {
      test('gets the info route with the headers and decodes it', () async {
        stubHttp(200, {'mode': 'intelligence'});

        final info = await transport.info(
          headers: {'Authorization': 'Bearer t'},
        );

        expect(info.mode, RuntimeMode.intelligence);
        final request = sentRequest();
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse('http://runtime.test/api/copilotkit/info'),
        );
        expect(request.headers['Authorization'], 'Bearer t');
      });

      test('refuses once closed', () async {
        await transport.close();

        expect(() => transport.info(), throwsStateError);
      });
    });

    group('close', () {
      test('ends the runs in flight and closes their channels', () async {
        final events = transport.run(agentId: 'a', input: _input).toList();
        await pumpEventQueue();

        await transport.close();

        expect(await events, isEmpty);
        verify(channel.close).called(1);
      });

      test('refuses new runs and stops', () async {
        await transport.close();

        expect(
          () => transport.run(agentId: 'a', input: _input),
          throwsStateError,
        );
        expect(
          () => transport.stop(agentId: 'a', threadId: 't', runId: 'r'),
          throwsStateError,
        );
      });
    });
  });
}
