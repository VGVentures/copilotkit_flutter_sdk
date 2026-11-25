// cspell:ignore realtime
import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/memories/memory_channel_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:test/test.dart';

import '../../helpers/memory_metadata_fixture.dart';

class _MockChannel extends Mock implements PhoenixChannelsClient;

final Uri _socketUrl = Uri.parse('wss://realtime.test/client');

const _both = MemoryChannelCredentials(
  joinToken: 'user-token',
  joinCode: 'user-code',
  projectJoinToken: 'project-token',
  projectJoinCode: 'project-code',
);

void main() {
  group(MemoryChannelListener, () {
    late List<_MockChannel> channels;
    late List<StreamController<PhoenixEvent>> frames;
    late List<String> tokens;
    late List<Duration> delays;
    late int connects;
    late Future<void> Function(String topic) onJoin;

    _MockChannel newChannel(Uri url, Map<String, String> params) {
      expect(url, _socketUrl);
      tokens.add(params['join_token']!);
      final channel = _MockChannel();
      final controller = StreamController<PhoenixEvent>.broadcast();
      frames.add(controller);
      channels.add(channel);
      when(() => channel.events).thenAnswer((_) => controller.stream);
      when(channel.open).thenAnswer((_) async {});
      when(() => channel.join(any(), any())).thenAnswer((invocation) async {
        await onJoin(invocation.positionalArguments.first as String);
        return null;
      });
      when(channel.close).thenAnswer((_) async {
        if (!controller.isClosed) await controller.close();
      });
      return channel;
    }

    MemoryChannelListener build({
      Future<MemoryChannelCredentials> Function()? credentials,
      int maxFailures = 5,
    }) => MemoryChannelListener(
      socketUrl: _socketUrl,
      credentials: credentials ?? () async => _both,
      onConnected: () => connects++,
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
      tokens = [];
      delays = [];
      connects = 0;
      onJoin = (_) async {};
    });

    test('joins the user and the project channels on two sockets', () async {
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      expect(tokens, ['user-token', 'project-token']);
      verify(() => channels[0].join('user_meta:memories:user-code', {}));
      verify(() => channels[1].join('project_meta:memories:project-code', {}));
      expect(connects, 1);
      await subscription.cancel();
      verify(channels[0].close).called(1);
      verify(channels[1].close).called(1);
    });

    test('joins the project channel alone when only it is granted', () async {
      final subscription = build(
        credentials: () async => const MemoryChannelCredentials(
          projectJoinToken: 'project-token',
          projectJoinCode: 'project-code',
        ),
      ).events.listen((_) {});
      await pumpEventQueue();

      expect(tokens, ['project-token']);
      verify(
        () => channels.single.join('project_meta:memories:project-code', {}),
      );
      expect(connects, 1);
      await subscription.cancel();
    });

    test('streams the recorded events of both channels', () async {
      final events = <MemoryMetadataEvent>[];
      final subscription = build().events.listen(events.add);
      await pumpEventQueue();

      memoryMetadataFrames().forEach(frames[0].add);
      frames[1].add(
        PhoenixEvent(
          topic: 'project_meta:memories:project-code',
          event: 'memory_metadata',
          payload: memoryMetadataPayload('invalidated'),
        ),
      );
      await pumpEventQueue();

      // The two sockets don't order their events with each other.
      expect(
        events.map((event) => event.operation),
        unorderedEquals([
          MemoryMetadataOperation.created,
          MemoryMetadataOperation.created,
          MemoryMetadataOperation.created,
          MemoryMetadataOperation.invalidated,
          MemoryMetadataOperation.invalidated,
          MemoryMetadataOperation.invalidated,
        ]),
      );
      await subscription.cancel();
    });

    test('skips events it cannot read or does not know', () async {
      final events = <MemoryMetadataEvent>[];
      final subscription = build().events.listen(events.add);
      await pumpEventQueue();

      frames[0]
        ..add(
          const PhoenixEvent(
            topic: 'user_meta:memories:user-code',
            event: 'memory_metadata',
            payload: {'operation': 'merged'},
          ),
        )
        ..add(
          const PhoenixEvent(
            topic: 'user_meta:memories:user-code',
            event: 'presence_diff',
            payload: {},
          ),
        );
      await pumpEventQueue();

      expect(events, isEmpty);
      await subscription.cancel();
    });

    test('keeps the user channel when the project channel fails', () async {
      onJoin = (topic) async {
        if (topic.startsWith('project_meta')) throw Exception('denied');
      };
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      frames[1].addError(const PhoenixClosedException());
      await pumpEventQueue();

      expect(channels, hasLength(2));
      expect(connects, 1);
      expect(delays, isEmpty);
      await subscription.cancel();
    });

    test('opens both sockets again with new credentials when the user '
        'socket drops', () async {
      var asked = 0;
      final subscription = build(
        credentials: () async {
          asked++;
          return _both;
        },
      ).events.listen((_) {});
      await pumpEventQueue();

      frames[0].addError(const PhoenixClosedException(code: 1006));
      await pumpEventQueue();

      expect(asked, 2);
      expect(channels, hasLength(4));
      verify(channels[1].close).called(1);
      expect(connects, 2);
      expect(delays, [const Duration(milliseconds: 1)]);
      await subscription.cancel();
    });

    test(
      'treats a user socket that ends without an error as dropped',
      () async {
        final subscription = build().events.listen((_) {});
        await pumpEventQueue();

        await frames[0].close();
        await pumpEventQueue();

        expect(channels, hasLength(4));
        await subscription.cancel();
      },
    );

    test('gives up after maxFailures failures in a row', () async {
      final done = Completer<void>();
      Object? error;

      build(
        maxFailures: 3,
        credentials: () async => throw Exception('no credentials'),
      ).events.listen(
        (_) {},
        onError: (Object e) => error = e,
        onDone: done.complete,
      );
      await done.future;

      expect(channels, isEmpty);
      expect(connects, 0);
      expect(delays, [
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 2),
      ]);
      expect(
        error,
        isA<MemoryException>()
            .having((e) => e.code, 'code', MemoryErrorCode.realtimeUnavailable)
            .having((e) => e.message, 'message', contains('no credentials')),
      );
    });

    test('starts counting again after a join', () async {
      var joins = 0;
      onJoin = (topic) async {
        if (topic.startsWith('user_meta') && ++joins == 1) {
          throw Exception('refused');
        }
      };
      final subscription = build(maxFailures: 2).events.listen((_) {});
      await pumpEventQueue();

      // Failed, then joined (sockets 1 and 2), then dropped.
      frames[1].addError(const PhoenixClosedException());
      await pumpEventQueue();

      expect(connects, 2);
      expect(delays, [
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 1),
      ]);
      await subscription.cancel();
    });

    test('opens nothing when cancelled while asking for credentials', () async {
      final credentials = Completer<MemoryChannelCredentials>();
      final subscription = build(credentials: () => credentials.future).events
          .listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();
      credentials.complete(_both);
      await pumpEventQueue();

      expect(channels, isEmpty);
    });

    test('opens no project socket when cancelled while joining', () async {
      final joined = Completer<void>();
      onJoin = (_) => joined.future;
      final subscription = build().events.listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();
      joined.complete();
      await pumpEventQueue();

      expect(channels, hasLength(1));
      expect(connects, 0);
    });

    test('waits longer after each failure by default', () async {
      // Nothing listens on port 1, so every socket fails to open.
      final listener = MemoryChannelListener(
        socketUrl: Uri.parse('ws://127.0.0.1:1/client'),
        credentials: () async => _both,
        maxFailures: 2,
      );
      final watch = Stopwatch()..start();

      await expectLater(listener.events, emitsError(isA<MemoryException>()));

      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 90)),
      );
    });
  });
}
