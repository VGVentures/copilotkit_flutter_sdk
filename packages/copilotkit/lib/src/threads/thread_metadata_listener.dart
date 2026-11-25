// cspell:ignore realtime
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:copilotkit/src/threads/models/thread_metadata_event.dart';
import 'package:copilotkit/src/threads/models/threads_error_code.dart';
import 'package:copilotkit/src/threads/models/threads_exception.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';

/// Follows the user's thread metadata channel on the runtime's real-time
/// service, `user_meta:<joinCode>`, and streams its `thread_metadata` events.
///
/// Every socket asks for a fresh join token. A socket that drops is opened
/// again after a growing delay. After `maxFailures` failures in a row, with no
/// join in between, it gives up: [events] emits a [ThreadsException] with
/// [ThreadsErrorCode.realtimeUnavailable] and ends.
///
/// The service may push the same event more than once, so apply events in a
/// way that repeating one changes nothing.
class ThreadMetadataListener({
  required final Uri _socketUrl,
  required final String _joinCode,
  required final Future<String> Function() _joinToken,
  PhoenixChannelsClient Function(Uri socketUrl, Map<String, String> params)?
  channelFactory,
  final int _maxFailures = 5,
  Duration Function(int failures)? retryDelay,
}) {
  /// Creates a listener for the channel of `joinCode` on the socket at
  /// `socketUrl`, asking `joinToken` for the token of each socket.
  ///
  /// `retryDelay` gives the wait before the next socket after that many
  /// failures in a row: from 100 ms, doubling, up to 10 seconds by default.
  /// `channelFactory` creates the Phoenix client of each socket.
  this;

  final PhoenixChannelsClient Function(Uri, Map<String, String>)
  _channelFactory =
      channelFactory ??
      ((url, params) => PhoenixChannelsClient(clientUrl: url, params: params));

  final Duration Function(int) _retryDelay = retryDelay ?? _defaultRetryDelay;

  /// The events of the channel, from when the stream is listened to until it
  /// is cancelled. Each listen follows the channel on its own sockets.
  Stream<ThreadMetadataEvent> get events {
    late final StreamController<ThreadMetadataEvent> controller;
    PhoenixChannelsClient? channel;
    var cancelled = false;

    Future<void> follow() async {
      var failures = 0;
      Object? lastError;
      while (!cancelled) {
        final dropped = Completer<Object>();
        try {
          final token = await _joinToken();
          if (cancelled) return;
          final current = channel = _channelFactory(_socketUrl, {
            'join_token': token,
          });
          // Listen before opening: early frames are lost otherwise.
          current.events.listen(
            (event) => _onEvent(event, controller),
            onError: (Object error) {
              if (!dropped.isCompleted) dropped.complete(error);
            },
            onDone: () {
              if (!dropped.isCompleted) {
                dropped.complete(const PhoenixClosedException());
              }
            },
          );
          await current.open();
          await current.join('user_meta:$_joinCode', const {});
          failures = 0;
          lastError = await dropped.future;
        } on Object catch (error) {
          lastError = error;
        }
        await channel?.close();
        if (cancelled) return;
        if (++failures >= _maxFailures) {
          controller.addError(
            ThreadsException(
              code: ThreadsErrorCode.realtimeUnavailable,
              message:
                  'The thread metadata channel failed $failures times in a '
                  'row: $lastError',
            ),
          );
          await controller.close();
          return;
        }
        await Future<void>.delayed(_retryDelay(failures));
      }
    }

    controller = StreamController(
      onListen: () => unawaited(follow()),
      onCancel: () async {
        cancelled = true;
        await channel?.close();
      },
    );
    return controller.stream;
  }

  void _onEvent(
    PhoenixEvent event,
    StreamController<ThreadMetadataEvent> controller,
  ) {
    if (event.event != 'thread_metadata') return;
    try {
      controller.add(ThreadMetadataEvent.fromJson(event.payload));
    } on Object catch (error) {
      developer.log(
        'Skipped a thread_metadata event this SDK cannot read: $error',
        name: 'copilotkit',
        level: 900, // WARNING
      );
    }
  }

  static Duration _defaultRetryDelay(int failures) => Duration(
    milliseconds: math.min(100 * math.pow(2, failures - 1).toInt(), 10000),
  );
}
