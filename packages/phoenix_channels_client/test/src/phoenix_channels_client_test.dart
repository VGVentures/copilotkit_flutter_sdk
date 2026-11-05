import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:phoenix_channels_client/src/phoenix_frame.dart';
import 'package:test/test.dart';

import '../helpers/fake_socket.dart';

void main() {
  group(PhoenixChannelsClient, () {
    late FakeSocket socket;

    setUp(() => socket = FakeSocket());

    PhoenixChannelsClient createClient({
      Duration heartbeatInterval = const Duration(minutes: 1),
      Duration replyTimeout = const Duration(seconds: 1),
    }) {
      final client = PhoenixChannelsClient(
        clientUrl: Uri.parse('wss://example.test/client'),
        params: const {'join_token': 'token'},
        heartbeatInterval: heartbeatInterval,
        replyTimeout: replyTimeout,
        connect: socket.connect,
      );
      addTearDown(client.close);
      return client;
    }

    /// Collects what [client.events] reports.
    ({List<PhoenixEvent> events, List<Object> errors, Future<void> done})
    listenTo(PhoenixChannelsClient client) {
      final events = <PhoenixEvent>[];
      final errors = <Object>[];
      final done = Completer<void>();
      client.events.listen(
        events.add,
        onError: errors.add,
        onDone: done.complete,
      );
      return (events: events, errors: errors, done: done.future);
    }

    group('open', () {
      test(
        'connects to the socket url with the params and the version',
        () async {
          final client = createClient();

          await client.open();

          expect(
            socket.connectedTo.toString(),
            'wss://example.test/client/websocket?join_token=token&vsn=2.0.0',
          );
        },
      );

      test('throws when the handshake fails, and can try again', () async {
        socket.failHandshake(Exception('refused'));
        final client = createClient();

        await expectLater(client.open, throwsException);
        await expectLater(() => client.join('t', const {}), throwsStateError);
      });

      test('throws a StateError when it is already open', () async {
        final client = createClient();
        await client.open();

        await expectLater(client.open, throwsStateError);
      });

      test('throws a StateError when it was closed', () async {
        final client = createClient();
        await client.close();

        await expectLater(client.open, throwsStateError);
      });
    });

    group('join', () {
      test('sends the join and returns the response of an ok reply', () async {
        final client = createClient();
        await client.open();

        final reply = client.join('thread:1', {'stream_mode': 'run'});
        await socket.settle();
        final request = socket.sentFrames.single;
        socket.serverSends(socket.replyTo(request, response: {'a': 1}));

        expect(
          request,
          const PhoenixFrame(
            joinRef: '1',
            ref: '1',
            topic: 'thread:1',
            event: 'phx_join',
            payload: {'stream_mode': 'run'},
          ),
        );
        expect(await reply, {'a': 1});
      });

      test('throws a PhoenixReplyException for an error reply', () async {
        final client = createClient();
        await client.open();

        final reply = client.join('thread:1', const {});
        await socket.settle();
        socket.serverSends(
          socket.replyTo(
            socket.sentFrames.single,
            status: 'error',
            response: {'reason': 'denied'},
          ),
        );

        await expectLater(
          reply,
          throwsA(
            const PhoenixReplyException(
              status: 'error',
              response: {'reason': 'denied'},
            ),
          ),
        );
      });

      test('names the status unknown when the reply has none', () async {
        final client = createClient();
        await client.open();

        final reply = client.join('thread:1', const {});
        await socket.settle();
        final request = socket.sentFrames.single;
        socket.serverSends(
          PhoenixFrame(
            joinRef: request.joinRef,
            ref: request.ref,
            topic: request.topic,
            event: 'phx_reply',
            payload: const {'response': 7},
          ),
        );

        await expectLater(
          reply,
          throwsA(const PhoenixReplyException(status: 'unknown', response: 7)),
        );
      });

      test('throws a TimeoutException when nothing answers', () async {
        final client = createClient(
          replyTimeout: const Duration(milliseconds: 20),
        );
        await client.open();

        await expectLater(
          client.join('thread:1', const {}),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('throws a StateError before the client is open', () async {
        final client = createClient();

        await expectLater(
          () => client.join('thread:1', const {}),
          throwsStateError,
        );
      });
    });

    group('push', () {
      test('sends the event with the join ref and a new ref', () async {
        final client = createClient();
        await client.open();
        final joined = client.join('thread:1', const {});
        await socket.settle();
        socket.serverSends(socket.replyTo(socket.sentFrames.single));
        await joined;

        final reply = client.push('thread:1', 'stop_run', {'run_id': 'r'});
        await socket.settle();
        final request = socket.sentFrames.last;
        socket.serverSends(socket.replyTo(request, response: {'ok': true}));

        expect(
          request,
          const PhoenixFrame(
            joinRef: '1',
            ref: '2',
            topic: 'thread:1',
            event: 'stop_run',
            payload: {'run_id': 'r'},
          ),
        );
        expect(await reply, {'ok': true});
      });
    });

    group('events', () {
      test('emit what the server pushes', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        socket.serverSends(
          const PhoenixFrame(
            topic: 'thread:1',
            event: 'ag_ui_event',
            payload: {'type': 'RUN_STARTED'},
          ),
        );
        await socket.settle();

        expect(heard.events, [
          const PhoenixEvent(
            topic: 'thread:1',
            event: 'ag_ui_event',
            payload: {'type': 'RUN_STARTED'},
          ),
        ]);
      });

      test('skip a reply nobody waits for', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        socket.serverSends(
          const PhoenixFrame(
            ref: '99',
            topic: 't',
            event: 'phx_reply',
            payload: {'status': 'ok'},
          ),
        );
        await socket.settle();

        expect(heard.events, isEmpty);
        expect(heard.errors, isEmpty);
      });

      test('skip a binary frame', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        socket.serverSendsRaw([1, 2, 3]);
        await socket.settle();

        expect(heard.events, isEmpty);
        expect(heard.errors, isEmpty);
      });

      test('report a malformed frame and keep going', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        socket
          ..serverSendsRaw('not json')
          ..serverSends(
            const PhoenixFrame(topic: 't', event: 'e', payload: {}),
          );
        await socket.settle();

        expect(heard.errors.single, isA<FormatException>());
        expect(heard.events, hasLength(1));
      });
    });

    group('when the connection ends', () {
      test(
        'the server closing it is reported with the code and reason',
        () async {
          final client = createClient();
          final heard = listenTo(client);
          await client.open();

          await socket.serverCloses(code: 1006, reason: 'gone');
          await socket.settle();

          expect(heard.errors, [
            const PhoenixClosedException(code: 1006, reason: 'gone'),
          ]);
        },
      );

      test('it is reported once however it ends', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        socket.streamFails(Exception('boom'));
        await socket.serverCloses();
        await socket.settle();

        expect(heard.errors, hasLength(1));
        expect(heard.errors.single, isException);
      });

      test('a push waiting for a reply fails with it', () async {
        final client = createClient();
        await client.open();

        final reply = expectLater(
          client.push('t', 'e', const {}),
          throwsA(const PhoenixClosedException(code: 1001)),
        );
        await socket.settle();
        await socket.serverCloses(code: 1001);

        await reply;
      });

      test('a later push throws a PhoenixClosedException', () async {
        final client = createClient();
        await client.open();
        await socket.serverCloses();
        await socket.settle();

        await expectLater(
          () => client.push('t', 'e', const {}),
          throwsA(isA<PhoenixClosedException>()),
        );
      });

      test('close still closes the socket and ends the events', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();
        socket.streamFails(Exception('boom'));
        await socket.settle();

        await client.close();
        await heard.done;

        expect(socket.closedByClient, isTrue);
      });
    });

    group('heartbeat', () {
      List<PhoenixFrame> beats() =>
          socket.sentFrames.where((frame) => frame.topic == 'phoenix').toList();

      test('is sent on the phoenix topic at the interval', () async {
        final client = createClient(
          heartbeatInterval: const Duration(milliseconds: 10),
        );
        await client.open();

        await socket.until(() => beats().length >= 2);

        expect(beats().first.event, 'heartbeat');
        expect(beats().first.joinRef, isNull);
        expect(
          beats().map((frame) => frame.ref).toSet(),
          hasLength(beats().length),
        );
      });

      test('keeps the connection while the server answers', () async {
        socket.onFrame = (frame) =>
            scheduleMicrotask(() => socket.serverSends(socket.replyTo(frame)));
        final client = createClient(
          heartbeatInterval: const Duration(milliseconds: 10),
        );
        final heard = listenTo(client);
        await client.open();

        await socket.until(() => beats().length >= 4);

        expect(heard.errors, isEmpty);
        expect(socket.closedByClient, isFalse);
      });

      test('drops the connection when the server does not answer', () async {
        final client = createClient(
          heartbeatInterval: const Duration(milliseconds: 10),
          replyTimeout: const Duration(milliseconds: 10),
        );
        final heard = listenTo(client);
        await client.open();

        await socket.until(() => socket.closedByClient);
        await socket.settle();

        expect(heard.errors, hasLength(1));
        expect(heard.errors.single, isA<TimeoutException>());
        await expectLater(
          () => client.push('t', 'e', const {}),
          throwsA(isA<PhoenixClosedException>()),
        );
      });

      test('is not reported twice when the server closes meanwhile', () async {
        final client = createClient(
          heartbeatInterval: const Duration(milliseconds: 10),
        );
        final heard = listenTo(client);
        await client.open();
        await socket.until(() => beats().isNotEmpty);

        await socket.serverCloses();
        await socket.settle(const Duration(milliseconds: 30));

        expect(heard.errors.single, isA<PhoenixClosedException>());
      });
    });

    group('close', () {
      test('closes the socket and ends the events without an error', () async {
        final client = createClient();
        final heard = listenTo(client);
        await client.open();

        await client.close();
        await heard.done;

        expect(socket.closedByClient, isTrue);
        expect(heard.errors, isEmpty);
      });

      test('fails a push waiting for a reply', () async {
        final client = createClient();
        await client.open();

        final reply = expectLater(
          client.push('t', 'e', const {}),
          throwsA(const PhoenixClosedException()),
        );
        await socket.settle();
        await client.close();

        await reply;
      });

      test('can be called twice', () async {
        final client = createClient();
        await client.open();

        await client.close();
        await client.close();

        verify(() => socket.sink.close()).called(1);
      });

      test('stops the heartbeat', () async {
        final client = createClient(
          heartbeatInterval: const Duration(milliseconds: 10),
        );
        await client.open();
        await socket.until(() => socket.sentFrames.isNotEmpty);

        await client.close();
        final sent = socket.sentFrames.length;
        await socket.settle(const Duration(milliseconds: 60));

        expect(socket.sentFrames, hasLength(sent));
      });

      test('works before the client was opened', () async {
        final client = createClient();

        await client.close();

        expect(socket.closedByClient, isFalse);
      });

      test('makes a later push throw a PhoenixClosedException', () async {
        final client = createClient();
        await client.open();
        await client.close();

        await expectLater(
          () => client.push('t', 'e', const {}),
          throwsA(isA<PhoenixClosedException>()),
        );
      });
    });
  });
}
