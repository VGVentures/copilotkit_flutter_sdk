// cspell:ignore realtime
import 'dart:async';

import 'package:copilotkit/src/trajectory/trajectory.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

import '../../helpers/trajectory_fixture.dart';

class _MockTrajectoryClient extends Mock implements TrajectoryClient;

class _MockChannel extends Mock implements PhoenixChannelsClient;

final TrajectoryGrant _grant = TrajectoryGrant(
  joinToken: 'token',
  clientUrl: Uri.parse('wss://realtime.test/client'),
  topic: 'trajectory:t1',
);

const _now = 1764100000000;

void main() {
  group(TrajectorySession, () {
    late _MockTrajectoryClient client;
    late List<_MockChannel> channels;
    late List<StreamController<PhoenixEvent>> sockets;
    late List<Map<String, Object?>> batches;
    late List<TrajectoryException> errors;
    late List<Duration> delays;

    /// How the next pushes are answered, in order; `null` is the default
    /// receipt that accepts the whole batch.
    late List<Future<Object?> Function(Map<String, Object?> payload)?> replies;
    late Future<void> Function() onJoin;

    Object? accept(Map<String, Object?> payload) {
      final events = payload['events']! as List;
      return {
        'accepted': events.length,
        'rejected': 0,
        'highestSeq': events.isEmpty
            ? null
            : ((events.last as Map)['value']! as Map)['seq'],
      };
    }

    _MockChannel newChannel(Uri url, Map<String, String> params) {
      expect(url, _grant.clientUrl);
      expect(params, {'join_token': 'token'});
      final channel = _MockChannel();
      final socket = StreamController<PhoenixEvent>.broadcast();
      channels.add(channel);
      sockets.add(socket);
      when(() => channel.events).thenAnswer((_) => socket.stream);
      when(channel.open).thenAnswer((_) async {});
      when(() => channel.join(any(), any())).thenAnswer((_) async {
        await onJoin();
        return null;
      });
      when(() => channel.push(any(), any(), any())).thenAnswer((invocation) {
        final payload =
            invocation.positionalArguments[2] as Map<String, Object?>;
        batches.add(payload);
        final reply = replies.isEmpty ? null : replies.removeAt(0);
        return reply == null ? Future.value(accept(payload)) : reply(payload);
      });
      when(channel.close).thenAnswer((_) async {
        if (!socket.isClosed) await socket.close();
      });
      return channel;
    }

    TrajectorySession build({
      int maxBatchEvents = 50,
      int maxBatchBytes = 64 * 1024,
      int maxEventBytes = 16 * 1024,
      bool withErrorHandler = true,
    }) => TrajectorySession(
      client: client,
      onError: withErrorHandler ? errors.add : null,
      channelFactory: newChannel,
      clock: () => _now,
      reconnectDelay: (attempt) {
        delays.add(Duration(seconds: attempt));
        return Duration(seconds: attempt);
      },
      maxBatchEvents: maxBatchEvents,
      maxBatchBytes: maxBatchBytes,
      maxEventBytes: maxEventBytes,
    );

    List<String> codes() => [for (final error in errors) error.code];

    List<Object?> sentNames() => [
      for (final batch in batches)
        for (final event in batch['events']! as List) (event as Map)['name'],
    ];

    setUp(() {
      client = _MockTrajectoryClient();
      channels = [];
      sockets = [];
      batches = [];
      errors = [];
      delays = [];
      replies = [];
      onJoin = () async {};
      when(() => client.connect(any())).thenAnswer((_) async => _grant);
    });

    group('start', () {
      test('joins the channel of the grant and returns the id', () async {
        final session = build();

        expect(await session.start(trajectoryId: 't1'), 't1');

        verify(() => client.connect('t1')).called(1);
        verify(() => channels.single.join('trajectory:t1', {})).called(1);
        expect(session.isCapturing, isTrue);
        expect(session.trajectoryId, 't1');
      });

      test('makes up an id when none is given', () async {
        final id = await build().start();

        expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      });

      test('returns the same start for the same trajectory', () async {
        final session = build();
        final first = session.start(trajectoryId: 't1');

        expect(session.start(trajectoryId: 't1'), same(first));
        expect(session.start(), same(first));
        await first;
        verify(() => client.connect('t1')).called(1);
      });

      test('stops the current trajectory to start another', () async {
        final session = build();
        await session.start(trajectoryId: 't1');

        expect(await session.start(trajectoryId: 't2'), 't2');

        verify(channels.first.close).called(1);
        verify(() => client.connect('t2')).called(1);
      });

      test('ends with null when the runtime refuses the grant', () async {
        when(() => client.connect(any())).thenThrow(
          const TrajectoryException(
            code: 'TRAJECTORIES_NOT_ENABLED',
            message: 'no',
            statusCode: 403,
          ),
        );
        final session = build();

        expect(await session.start(trajectoryId: 't1'), isNull);

        expect(codes(), ['TRAJECTORIES_NOT_ENABLED']);
        expect(session.trajectoryId, isNull);
        expect(delays, isEmpty);
      });

      test('maps the recorded join refusal and ends the capture', () async {
        final refusal = trajectoryRow('join');
        onJoin = () async => throw PhoenixReplyException(
          status: refusal['status']! as String,
          response: refusal['response'],
        );
        final session = build();

        expect(await session.start(trajectoryId: 't1'), isNull);

        expect(codes(), ['TRAJECTORIES_ENTITLEMENT_UNAVAILABLE']);
        verify(channels.single.close).called(1);
      });

      test('maps other join failures', () async {
        for (final (failure, code) in [
          (
            const PhoenixReplyException(status: 'error', response: 'odd'),
            'JOIN_FAILED',
          ),
          (TimeoutException('join'), 'CONNECTION_TIMEOUT'),
          (const PhoenixClosedException(), 'CONNECTION_LOST'),
        ]) {
          errors.clear();
          onJoin = () async => throw failure;

          expect(await build().start(trajectoryId: 't1'), isNull);
          expect(codes(), [code]);
        }
      });

      test('returns null when stopped while connecting', () async {
        final grant = Completer<TrajectoryGrant>();
        when(() => client.connect(any())).thenAnswer((_) => grant.future);
        final session = build();
        final start = session.start(trajectoryId: 't1');

        await session.stop();
        grant.complete(_grant);

        expect(await start, isNull);
        expect(channels, isEmpty);
      });

      test('returns null when stopped while joining', () async {
        final joined = Completer<void>();
        onJoin = () => joined.future;
        final session = build();
        final start = session.start(trajectoryId: 't1');
        await pumpEventQueue();

        final stop = session.stop();
        joined.complete();
        await stop;

        expect(await start, isNull);
        expect(session.isCapturing, isFalse);
      });

      test('reports nothing for a refusal after a stop', () async {
        final grant = Completer<TrajectoryGrant>();
        when(() => client.connect(any())).thenAnswer((_) => grant.future);
        final session = build();
        final start = session.start(trajectoryId: 't1');

        await pumpEventQueue();
        verify(() => client.connect('t1')).called(1);

        await session.stop();
        grant.completeError(
          const TrajectoryException(code: 'X', message: 'late'),
        );

        expect(await start, isNull);
        expect(errors, isEmpty);
      });
    });

    group('emit', () {
      test('ignores events before the first join', () async {
        final session = build()..emit('deal.approved', const {'id': 1});
        await session.start(trajectoryId: 't1');
        await session.stop();

        expect(batches, isEmpty);
        expect(errors, isEmpty);
      });

      test('sends a batch two seconds after the first event', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..emit('deal.approved', const {'dealId': 'd-1'})
            ..emit('note', 'plain text');
          async.elapse(const Duration(milliseconds: 1999));
          expect(batches, isEmpty);
          async.elapse(const Duration(milliseconds: 1));

          expect(batches.single, {
            'events': [
              {
                'type': 'CUSTOM',
                'name': 'deal.approved',
                'timestamp': _now,
                'value': {'dealId': 'd-1', 'seq': _now * 1000},
              },
              {
                'type': 'CUSTOM',
                'name': 'note',
                'timestamp': _now,
                'value': {'data': 'plain text', 'seq': _now * 1000 + 1},
              },
            ],
            'dropped': 0,
          });
          verify(() => channels.single.push('trajectory:t1', 'events', any()))
              .called(1);
        });
      });

      test('wraps an object that has its own seq', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.emit('x', const {'seq': 7}))
            ..elapse(const Duration(seconds: 2));

          final event = (batches.single['events']! as List).single as Map;
          expect(event['value'], {
            'data': {'seq': 7},
            'seq': _now * 1000,
          });
        });
      });

      test('sends at once at the batch size', () {
        fakeAsync((async) {
          final session = build(maxBatchEvents: 2);
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..emit('a', null)
            ..emit('b', null);
          async.flushMicrotasks();

          expect(sentNames(), ['a', 'b']);
        });
      });

      test('keeps one batch in flight and sends the rest after it', () {
        fakeAsync((async) {
          final first = Completer<Object?>();
          replies = [(_) => first.future];
          final session = build(maxBatchEvents: 1);
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..emit('a', null)
            ..emit('b', null);
          async.flushMicrotasks();
          expect(batches, hasLength(1));

          first.complete({'accepted': 1, 'rejected': 0, 'highestSeq': 1});
          async.flushMicrotasks();

          expect(sentNames(), ['a', 'b']);
        });
      });

      test('refuses invalid names', () async {
        final session = build();
        await session.start(trajectoryId: 't1');

        for (final name in ['', '  ', 'a' * 201, 'a\u0000b', 'click']) {
          session.emit(name, null);
        }

        expect(codes(), List.filled(5, 'INVALID_EVENT'));
      });

      test('drops a value that is not JSON', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.emit('x', Object()))
            ..run((_) => session.emit('y', null))
            ..elapse(const Duration(seconds: 2));

          expect(codes(), ['INVALID_EVENT']);
          expect(batches.single['dropped'], 1);
        });
      });

      test('drops an event over the event size', () {
        fakeAsync((async) {
          final session = build(maxEventBytes: 200);
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.emit('big', 'x' * 300))
            ..run((_) => session.emit('small', null))
            ..elapse(const Duration(seconds: 2));

          expect(codes(), ['EVENT_TOO_LARGE']);
          expect(sentNames(), ['small']);
          expect(batches.single['dropped'], 1);
        });
      });

      test('sends the queue first when the next event would not fit', () {
        fakeAsync((async) {
          final session = build(maxBatchBytes: 400, maxEventBytes: 300);
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..emit('first', 'x' * 150)
            ..emit('second', 'x' * 150);
          async.flushMicrotasks();

          // The second goes as soon as the first batch is answered.
          expect(batches, hasLength(2));
          expect(sentNames(), ['first', 'second']);
        });
      });

      test('drops an event that fits no batch while one is in flight', () {
        fakeAsync((async) {
          final first = Completer<Object?>();
          replies = [(_) => first.future];
          final session = build(
            maxBatchEvents: 1,
            maxBatchBytes: 400,
            maxEventBytes: 300,
          );
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..emit('first', null)
            ..emit('second', 'x' * 150)
            ..emit('third', 'x' * 150);
          async.flushMicrotasks();

          expect(codes(), ['EVENTS_DROPPED']);
          first.complete({'accepted': 1, 'rejected': 0, 'highestSeq': 1});
          async.flushMicrotasks();
          expect(sentNames(), ['first', 'second']);
          expect(batches.last['dropped'], 1);
        });
      });

      test('reports SEQUENCE_EXHAUSTED past the largest safe integer', () {
        fakeAsync((async) {
          final session = TrajectorySession(
            client: client,
            onError: errors.add,
            channelFactory: newChannel,
            clock: () => 9007199254741,
          );
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.emit('x', null));

          expect(codes(), ['SEQUENCE_EXHAUSTED']);
        });
      });

      test('logs problems without an error handler', () async {
        final session = build(withErrorHandler: false);
        await session.start(trajectoryId: 't1');

        session.emit('click', null);

        expect(errors, isEmpty);
      });
    });

    group('receipts', () {
      void sendOne(FakeAsync async, TrajectorySession session) {
        unawaited(session.start(trajectoryId: 't1'));
        async
          ..flushMicrotasks()
          ..run((_) => session.emit('a', null))
          ..elapse(const Duration(seconds: 2));
      }

      test('reports PERSISTENCE_UNKNOWN for an invalid receipt', () {
        fakeAsync((async) {
          replies = [
            (_) async => const {'accepted': 5},
          ];
          sendOne(async, build());

          expect(codes(), ['PERSISTENCE_UNKNOWN']);
        });
      });

      test('reports EVENTS_REJECTED for rejected events', () {
        fakeAsync((async) {
          replies = [
            (_) async => const {
              'accepted': 0,
              'rejected': 1,
              'highestSeq': null,
            },
          ];
          sendOne(async, build());

          expect(codes(), ['EVENTS_REJECTED']);
        });
      });

      test('counts a refused batch as dropped for the next one', () {
        fakeAsync((async) {
          final row = trajectoryRow('invalid-batch');
          replies = [
            (_) async => throw PhoenixReplyException(
              status: row['status']! as String,
              response: row['response'],
            ),
          ];
          final session = build();
          sendOne(async, session);

          // The count goes out at once, in a batch of its own.
          expect(codes(), ['INVALID_BATCH']);
          expect(batches.last, {'events': <Object?>[], 'dropped': 1});
        });
      });

      test('reports PERSISTENCE_UNKNOWN for other refusals and timeouts', () {
        fakeAsync((async) {
          replies = [
            (_) async => throw const PhoenixReplyException(
              status: 'error',
              response: {'reason': 'odd'},
            ),
            (_) async => throw TimeoutException('push'),
          ];
          final session = build();
          sendOne(async, session);
          session.emit('b', null);
          async.elapse(const Duration(seconds: 2));

          expect(codes(), ['PERSISTENCE_UNKNOWN', 'PERSISTENCE_UNKNOWN']);
        });
      });

      test('ends the capture on the recorded unauthorized refusal', () {
        fakeAsync((async) {
          final row = trajectoryRow('unauthorized');
          replies = [
            (_) async => throw PhoenixReplyException(
              status: row['status']! as String,
              response: row['response'],
            ),
          ];
          final session = build();
          sendOne(async, session);

          expect(codes(), ['UNAUTHORIZED']);
          expect(session.isCapturing, isFalse);
          expect(session.trajectoryId, isNull);
          verify(channels.single.close).called(1);
          expect(delays, isEmpty);
        });
      });

      test('ends the capture on a trajectory mismatch', () {
        fakeAsync((async) {
          replies = [
            (_) async => throw const PhoenixReplyException(
              status: 'error',
              response: {'reason': 'trajectory_mismatch'},
            ),
          ];
          sendOne(async, build());

          expect(codes(), ['TRAJECTORY_MISMATCH']);
        });
      });
    });

    group('reconnect', () {
      test('counts the queue as dropped and reconnects with a new grant', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.emit('queued', null));

          sockets.first.addError(const PhoenixClosedException());
          async.flushMicrotasks();
          expect(codes(), ['CONNECTION_LOST']);
          expect(session.isCapturing, isFalse);

          // Lost while reconnecting.
          session.emit('meanwhile', null);
          async.elapse(const Duration(seconds: 1));

          verify(() => client.connect('t1')).called(2);
          expect(session.isCapturing, isTrue);
          expect(batches.single, {'events': <Object?>[], 'dropped': 2});
        });
      });

      test('treats a socket that ends without an error as lost', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          unawaited(sockets.first.close());
          async.elapse(const Duration(seconds: 1));

          expect(codes(), ['CONNECTION_LOST']);
          expect(channels, hasLength(2));
          expect(session.isCapturing, isTrue);
        });
      });

      test('keeps trying while the failures are retryable', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();
          var calls = 0;
          when(() => client.connect(any())).thenAnswer((_) async {
            if (++calls < 3) {
              throw const TrajectoryException(
                code: 'CONNECTION_FAILED',
                message: 'down',
                isRetryable: true,
              );
            }
            return _grant;
          });

          sockets.first.addError(const PhoenixClosedException());
          async.elapse(const Duration(seconds: 10));

          expect(delays, [
            const Duration(seconds: 1),
            const Duration(seconds: 1),
            const Duration(seconds: 2),
          ]);
          expect(session.isCapturing, isTrue);
        });
      });

      test('ends the capture on a refusal while reconnecting', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();
          when(() => client.connect(any())).thenThrow(
            const TrajectoryException(code: 'UNAUTHORIZED', message: 'no'),
          );

          sockets.first.addError(const PhoenixClosedException());
          async.elapse(const Duration(seconds: 2));

          expect(codes(), ['CONNECTION_LOST', 'UNAUTHORIZED']);
          expect(session.trajectoryId, isNull);
        });
      });

      test('stops reconnecting once stopped', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          sockets.first.addError(const PhoenixClosedException());
          async.flushMicrotasks();
          unawaited(session.stop());
          async.elapse(const Duration(seconds: 5));

          verify(() => client.connect('t1')).called(1);
        });
      });

      test('stops a retry loop once stopped', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();
          when(() => client.connect(any())).thenThrow(
            const TrajectoryException(
              code: 'CONNECTION_FAILED',
              message: 'down',
              isRetryable: true,
            ),
          );
          sockets.first.addError(const PhoenixClosedException());
          async.elapse(const Duration(seconds: 1));

          unawaited(session.stop());
          async.elapse(const Duration(seconds: 10));

          expect(delays, hasLength(2));
        });
      });

      test('ignores the end of a socket it replaced', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();
          // Starting t2 closes t1's socket, which must not look lost.
          unawaited(session.start(trajectoryId: 't2'));
          async.flushMicrotasks();

          expect(codes(), isEmpty);
          expect(session.trajectoryId, 't2');
        });
      });
    });

    group('linkThread', () {
      test('links each thread once while connected', () {
        fakeAsync((async) {
          final session = build()..linkThread('before');
          unawaited(session.start(trajectoryId: 't1'));
          async.flushMicrotasks();

          session
            ..linkThread('a')
            ..linkThread('a')
            ..linkThread('b');
          async.elapse(const Duration(seconds: 2));

          expect(sentNames(), ['thread.linked', 'thread.linked']);
          expect(((batches.single['events']! as List).first as Map)['value'], {
            'threadId': 'a',
            'seq': _now * 1000,
          });
        });
      });

      test('links a thread again after a reconnect', () {
        fakeAsync((async) {
          final session = build();
          unawaited(session.start(trajectoryId: 't1'));
          async
            ..flushMicrotasks()
            ..run((_) => session.linkThread('a'))
            ..elapse(const Duration(seconds: 2));
          sockets.first.addError(const PhoenixClosedException());
          async.elapse(const Duration(seconds: 1));

          session.linkThread('a');
          async.elapse(const Duration(seconds: 2));

          expect(sentNames(), ['thread.linked', 'thread.linked']);
        });
      });
    });

    group('stop', () {
      test('sends what is queued, then closes the channel', () async {
        final session = build();
        await session.start(trajectoryId: 't1');
        session.record(TrajectoryBuiltInEvent.navigation, const {'to': '/a'});

        await session.stop();

        expect(sentNames(), ['navigation']);
        verify(channels.single.close).called(1);
        expect(session.trajectoryId, isNull);
        expect(errors, isEmpty);
      });

      test('reports what it could not send', () async {
        final session = build(maxBatchEvents: 1);
        replies = [(_) async => throw const PhoenixClosedException()];
        await session.start(trajectoryId: 't1');
        session.emit('a', null);
        await pumpEventQueue();

        await session.stop();

        expect(codes(), ['PERSISTENCE_UNKNOWN']);
      });

      test('reports events still queued after the last batch', () async {
        final session = build(maxBatchEvents: 1);
        final hang = Completer<Object?>();
        replies = [(_) => hang.future];
        await session.start(trajectoryId: 't1');
        session
          ..emit('a', null)
          ..emit('b', null);

        final stop = session.stop();
        hang.complete({'accepted': 1, 'rejected': 0, 'highestSeq': 1});
        await stop;

        expect(sentNames(), ['a', 'b']);
      });

      test('reports EVENTS_DROPPED when a batch fails on stop', () async {
        final session = build();
        await session.start(trajectoryId: 't1');
        session.emit('a', null);
        // The socket is gone before stop sends the queue.
        sockets.single.addError(const PhoenixClosedException());
        await pumpEventQueue();

        await session.stop();

        expect(codes(), ['CONNECTION_LOST', 'EVENTS_DROPPED']);
      });

      test('does nothing without a trajectory', () async {
        await build().stop();

        expect(errors, isEmpty);
      });
    });

    test('waits longer before each reconnect by default', () {
      fakeAsync((async) {
        final session = TrajectorySession(
          client: client,
          onError: errors.add,
          channelFactory: newChannel,
        );
        unawaited(session.start(trajectoryId: 't1'));
        async.flushMicrotasks();
        // Frames the server pushes on the trajectory channel are ignored.
        sockets.first.add(
          const PhoenixEvent(topic: 'trajectory:t1', event: 'odd', payload: {}),
        );
        session.emit('timed', null);
        async.flushMicrotasks();
        expect(session.isCapturing, isTrue);

        sockets.first.addError(const PhoenixClosedException());
        async.elapse(const Duration(milliseconds: 999));
        expect(channels, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(channels, hasLength(2));
      });
    });

    test('creates its own Phoenix client by default', () async {
      final session = TrajectorySession(client: client, onError: errors.add);
      when(() => client.connect(any())).thenAnswer(
        (_) async => TrajectoryGrant(
          joinToken: 'token',
          clientUrl: Uri.parse('ws://127.0.0.1:1/client'),
          topic: 'trajectory:t1',
        ),
      );

      expect(await session.start(trajectoryId: 't1'), isNull);
      expect(codes(), ['CONNECTION_LOST']);
    });
  });
}
