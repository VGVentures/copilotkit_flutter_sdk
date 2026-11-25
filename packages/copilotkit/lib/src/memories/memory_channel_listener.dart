// cspell:ignore realtime
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:copilotkit/src/memories/models/memory_channel_credentials.dart';
import 'package:copilotkit/src/memories/models/memory_error_code.dart';
import 'package:copilotkit/src/memories/models/memory_exception.dart';
import 'package:copilotkit/src/memories/models/memory_metadata_event.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';

/// Follows the memory channels the runtime grants, on its real-time service,
/// and streams their `memory_metadata` events.
///
/// The primary channel is the user's, or the project's when only the project
/// is granted. It decides the connection: `onConnected` is called each time
/// it joins, a primary socket that drops is opened again after a growing
/// delay with fresh credentials, and after `maxFailures` failures in a row,
/// with no join in between, [events] emits a [MemoryException] with
/// [MemoryErrorCode.realtimeUnavailable] and ends. The project's channel,
/// when both are granted, is followed on its own socket as a bonus: a
/// failure there is logged and changes nothing else.
///
/// The service may push the same event more than once, so apply events in a
/// way that repeating one changes nothing.
class MemoryChannelListener({
  required final Uri _socketUrl,
  required final Future<MemoryChannelCredentials> Function() _credentials,
  final void Function()? _onConnected,
  PhoenixChannelsClient Function(Uri socketUrl, Map<String, String> params)?
  channelFactory,
  final int _maxFailures = 5,
  Duration Function(int failures)? retryDelay,
}) {
  /// Creates a listener for the channels `credentials` grants, on the socket
  /// at `socketUrl`.
  ///
  /// `retryDelay` gives the wait before the next attempt after that many
  /// failures in a row: from 100 ms, doubling, up to 10 seconds by default.
  /// `channelFactory` creates the Phoenix client of each socket.
  this;

  final PhoenixChannelsClient Function(Uri, Map<String, String>)
  _channelFactory =
      channelFactory ??
      ((url, params) => PhoenixChannelsClient(clientUrl: url, params: params));

  final Duration Function(int) _retryDelay = retryDelay ?? _defaultRetryDelay;

  /// The events of the channels, from when the stream is listened to until
  /// it is cancelled. Each listen follows the channels on its own sockets.
  Stream<MemoryMetadataEvent> get events {
    late final StreamController<MemoryMetadataEvent> controller;
    final channels = <PhoenixChannelsClient>[];
    var cancelled = false;

    Future<void> closeAll() async {
      final open = [...channels];
      channels.clear();
      await Future.wait(open.map((channel) => channel.close()));
    }

    /// Opens a socket with [token], joins [topic] and passes its events on.
    /// Completes [dropped], if given, when the socket ends.
    Future<void> follow(
      String token,
      String topic, {
      Completer<Object>? dropped,
    }) async {
      final channel = _channelFactory(_socketUrl, {'join_token': token});
      channels.add(channel);
      // Listen before opening: early frames are lost otherwise.
      channel.events.listen(
        (event) => _onEvent(event, controller),
        onError: (Object error) {
          if (dropped != null && !dropped.isCompleted) dropped.complete(error);
        },
        onDone: () {
          if (dropped != null && !dropped.isCompleted) {
            dropped.complete(const PhoenixClosedException());
          }
        },
      );
      await channel.open();
      await channel.join(topic, const {});
    }

    Future<void> run() async {
      var failures = 0;
      Object? lastError;
      while (!cancelled) {
        final dropped = Completer<Object>();
        try {
          final credentials = await _credentials();
          if (cancelled) return;
          final userTopic = credentials.userTopic;
          final projectTopic = credentials.projectTopic;
          await follow(
            userTopic != null
                ? credentials.joinToken!
                : credentials.projectJoinToken!,
            userTopic ?? projectTopic!,
            dropped: dropped,
          );
          if (cancelled) return;
          failures = 0;
          _onConnected?.call();
          if (userTopic != null && projectTopic != null) {
            unawaited(
              follow(credentials.projectJoinToken!, projectTopic).catchError(
                (Object error) => developer.log(
                  'The project memory channel failed: $error',
                  name: 'copilotkit',
                  level: 900, // WARNING
                ),
              ),
            );
          }
          lastError = await dropped.future;
        } on Object catch (error) {
          lastError = error;
        }
        await closeAll();
        if (cancelled) return;
        if (++failures >= _maxFailures) {
          controller.addError(
            MemoryException(
              code: MemoryErrorCode.realtimeUnavailable,
              message:
                  'The memory channel failed $failures times in a row: '
                  '$lastError',
            ),
          );
          await controller.close();
          return;
        }
        await Future<void>.delayed(_retryDelay(failures));
      }
    }

    controller = StreamController(
      onListen: () => unawaited(run()),
      onCancel: () async {
        cancelled = true;
        await closeAll();
      },
    );
    return controller.stream;
  }

  void _onEvent(
    PhoenixEvent event,
    StreamController<MemoryMetadataEvent> controller,
  ) {
    if (event.event != 'memory_metadata') return;
    try {
      controller.add(MemoryMetadataEvent.fromJson(event.payload));
    } on Object catch (error) {
      developer.log(
        'Skipped a memory_metadata event this SDK cannot read: $error',
        name: 'copilotkit',
        level: 900, // WARNING
      );
    }
  }

  static Duration _defaultRetryDelay(int failures) => Duration(
    milliseconds: math.min(100 * math.pow(2, failures - 1).toInt(), 10000),
  );
}
