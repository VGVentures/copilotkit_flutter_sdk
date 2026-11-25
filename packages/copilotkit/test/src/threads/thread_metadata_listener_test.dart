// cspell:ignore realtime
import 'dart:async';

import 'package:copilotkit/src/threads/models/thread_metadata_event.dart';
import 'package:copilotkit/src/threads/models/thread_metadata_operation.dart';
import 'package:copilotkit/src/threads/models/threads_error_code.dart';
import 'package:copilotkit/src/threads/models/threads_exception.dart';
import 'package:copilotkit/src/threads/thread_metadata_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

import '../../helpers/thread_metadata_fixture.dart';

class _MockChannel extends Mock implements PhoenixChannelsClient;

final Uri _socketUrl = Uri.parse('wss://realtime.test/client');

void main() {
  group(ThreadMetadataListener, () {
    late List<_MockChannel> channels;
    late List<StreamController<PhoenixEvent>> frames;
    late List<Map<String, String>> params;
    late List<Duration> delays;
    late int tokens;
    late Future<void> Function(_MockChannel channel) onJoin;

    _MockChannel newChannel(Uri url, Map<String, String> given) {
      expect(url, _socketUrl);
      params.add(given);
      final channel = _MockChannel();
      final controller = StreamController<PhoenixEvent>.broadcast();
      frames.add(controller);
      channels.add(channel);
      when(() => channel.events).thenAnswer((_) => controller.stream);
      when(channel.open).thenAnswer((_) async {});
      when(() => channel.join(any(), any())).thenAnswer((_) async {
        await onJoin(channel);
        return null;
      });
      when(channel.close).thenAnswer((_) async {
        if (!controller.isClosed) await controller.close();
      });
      return channel;
    }

    ThreadMetadataListener build({
      Future<String> Function()? joinToken,
      int maxFailures = 5,
    }) => ThreadMetadataListener(
      socketUrl: _socketUrl,
      joinCode: 'code-1',
      joinToken: joinToken ?? () async => 'token-${++tokens}',
      channelFactory: newChannel,
      maxFailures: maxFailures,
      retryDelay: (failures) {
        delays.add(Duration(milliseconds: failures));
        return Duration.zero;
      },
    );

    setUp(() {
      channels = [];
      frames = [];
      params = [];
      delays = [];
      tokens = 0;
      onJoin = (_) async {};
    });

    test('joins the user channel with a fresh token', () async {
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      expect(params, [
        {'join_token': 'token-1'},
      ]);
      verify(channels.single.open).called(1);
      verify(() => channels.single.join('user_meta:code-1', {})).called(1);
      await subscription.cancel();
    });

    test('streams the recorded thread_metadata events in order', () async {
      final events = <ThreadMetadataEvent>[];
      final subscription = build().events.listen(events.add);
      await pumpEventQueue();

      threadMetadataFrames().forEach(frames.single.add);
      await pumpEventQueue();

      expect(events.map((event) => event.operation), [
        ThreadMetadataOperation.created,
        ThreadMetadataOperation.created,
        ThreadMetadataOperation.renamed,
        ThreadMetadataOperation.renamed,
        ThreadMetadataOperation.archived,
        ThreadMetadataOperation.unarchived,
        ThreadMetadataOperation.deleted,
      ]);
      await subscription.cancel();
    });

    test('skips an event it cannot read', () async {
      final events = <ThreadMetadataEvent>[];
      final subscription = build().events.listen(events.add);
      await pumpEventQueue();

      frames.single
        ..add(
          const PhoenixEvent(
            topic: 'user_meta:code-1',
            event: 'thread_metadata',
            payload: {'operation': 'merged', 'threadId': 't'},
          ),
        )
        ..add(
          PhoenixEvent(
            topic: 'user_meta:code-1',
            event: 'thread_metadata',
            payload: threadMetadataPayload('deleted'),
          ),
        );
      await pumpEventQueue();

      expect(events.single.operation, ThreadMetadataOperation.deleted);
      await subscription.cancel();
    });

    test('opens a new socket with a new token when one drops', () async {
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      frames.first.addError(const PhoenixClosedException(code: 1006));
      await pumpEventQueue();

      expect(params, [
        {'join_token': 'token-1'},
        {'join_token': 'token-2'},
      ]);
      verify(channels.first.close).called(1);
      expect(delays, [const Duration(milliseconds: 1)]);
      await subscription.cancel();
    });

    test('treats a socket that ends without an error as dropped', () async {
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      await frames.first.close();
      await pumpEventQueue();

      expect(channels, hasLength(2));
      await subscription.cancel();
    });

    test('gives up after maxFailures failures in a row', () async {
      onJoin = (_) async => throw Exception('join refused');
      final done = Completer<void>();
      Object? error;

      build(maxFailures: 3).events.listen(
        (_) {},
        onError: (Object e) => error = e,
        onDone: done.complete,
      );
      await done.future;

      expect(channels, hasLength(3));
      expect(delays, [
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 2),
      ]);
      expect(
        error,
        isA<ThreadsException>()
            .having((e) => e.code, 'code', ThreadsErrorCode.realtimeUnavailable)
            .having((e) => e.message, 'message', contains('join refused')),
      );
    });

    test('counts a failed token request as a failure', () async {
      final done = Completer<void>();
      Object? error;

      build(
        maxFailures: 2,
        joinToken: () async => throw Exception('no token'),
      ).events.listen(
        (_) {},
        onError: (Object e) => error = e,
        onDone: done.complete,
      );
      await done.future;

      expect(channels, isEmpty);
      expect(
        error,
        isA<ThreadsException>().having(
          (e) => e.message,
          'message',
          contains('no token'),
        ),
      );
    });

    test('starts counting again after a join', () async {
      var joins = 0;
      onJoin = (_) async {
        if (++joins == 1) throw Exception('join refused');
      };
      final subscription = build(maxFailures: 2).events.listen((_) {});
      await pumpEventQueue();

      // A failure, a join, then a drop: one failure in a row each time.
      frames[1].addError(const PhoenixClosedException());
      await pumpEventQueue();

      expect(channels, hasLength(3));
      expect(delays, [
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
      ]);
      await subscription.cancel();
    });

    test('closes the socket when cancelled', () async {
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();
      await pumpEventQueue();

      verify(channels.single.close).called(greaterThanOrEqualTo(1));
      expect(channels, hasLength(1));
    });

    test('opens no socket when cancelled while asking for a token', () async {
      final token = Completer<String>();
      final subscription = build(joinToken: () => token.future).events
          .listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();
      token.complete('late');
      await pumpEventQueue();

      expect(channels, isEmpty);
    });

    test('waits longer after each failure by default', () async {
      // Nothing listens on port 1, so every socket fails to open.
      final listener = ThreadMetadataListener(
        socketUrl: Uri.parse('ws://127.0.0.1:1/client'),
        joinCode: 'code-1',
        joinToken: () async => 'token',
        maxFailures: 2,
      );
      final watch = Stopwatch()..start();

      await expectLater(listener.events, emitsError(isA<ThreadsException>()));

      // One wait of 100 ms between the two failures.
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 90)),
      );
    });
  });
}
