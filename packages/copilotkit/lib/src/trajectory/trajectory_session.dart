import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:copilotkit/src/trajectory/models/trajectory_built_in_event.dart';
import 'package:copilotkit/src/trajectory/models/trajectory_exception.dart';
import 'package:copilotkit/src/trajectory/models/trajectory_grant.dart';
import 'package:copilotkit/src/trajectory/models/trajectory_receipt.dart';
import 'package:copilotkit/src/trajectory/trajectory_client.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';
import 'package:uuid/uuid.dart';

/// Captures one trajectory at a time: what the user does in the app, sent to
/// Intelligence for Automatic Learning, as `@copilotkit/core` 1.79 does.
///
/// [start] asks the runtime for a grant and joins the trajectory's channel.
/// Events are AG-UI `CUSTOM` events with a `seq` that only goes up. They are
/// batched: a batch goes out 2 seconds after its first event, at 50 events,
/// or before it would pass 64 KiB, and one batch at a time. An event over
/// 16 KiB is dropped. Events lost on the way (too large, the socket down, a
/// batch refused) are counted, and the count goes out with the next batch
/// as `dropped`.
///
/// Problems go to the error handler as a [TrajectoryException]. Once a
/// capture has started, a dropped connection reconnects with a new grant;
/// a refusal ends the capture. A failure before the first join ends it too.
class TrajectorySession({
  required final TrajectoryClient _client,
  final void Function(TrajectoryException error)? _onError,
  PhoenixChannelsClient Function(Uri socketUrl, Map<String, String> params)?
  channelFactory,
  int Function()? clock,
  Duration Function(int attempt)? reconnectDelay,
  final Duration _batchInterval = const Duration(seconds: 2),
  final int _maxBatchEvents = 50,
  final int _maxBatchBytes = 64 * 1024,
  final int _maxEventBytes = 16 * 1024,
  final Uuid _uuid = const Uuid(),
}) {
  /// Creates a session that gets its grants from `client` and reports
  /// problems to `onError`, or logs them without one.
  ///
  /// `channelFactory` creates the Phoenix client of each socket. `clock`
  /// gives the time in milliseconds since the epoch. `reconnectDelay` gives
  /// the wait before reconnect attempt `n`: 1 second, doubling, up to 10.
  this;

  /// The reasons of a refused batch whose events are counted as dropped.
  static const _rollbackReasons = {
    'invalid_batch',
    'batch_too_large',
    'batch_too_many_events',
    'trajectory_over_share',
    'trajectory_outbox_full',
    'unsupported_event',
  };

  /// The reasons of a refused join and their codes.
  static const _joinRefusals = {
    'trajectories_unavailable': 'TRAJECTORIES_UNAVAILABLE',
    'trajectories_not_enabled': 'TRAJECTORIES_NOT_ENABLED',
    'entitlement_unavailable': 'TRAJECTORIES_ENTITLEMENT_UNAVAILABLE',
    'marketplace_license_required': 'MARKETPLACE_LICENSE_REQUIRED',
  };

  static const _maxSafeInteger = 9007199254740991;

  final PhoenixChannelsClient Function(Uri, Map<String, String>)
  _channelFactory =
      channelFactory ??
      ((url, params) => PhoenixChannelsClient(clientUrl: url, params: params));

  final int Function() _clock =
      clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Duration Function(int) _reconnectDelay =
      reconnectDelay ?? _defaultReconnectDelay;

  /// The next `seq`, from the creation time in microseconds, for the life
  /// of the session.
  int? _nextSeq;

  String? _trajectoryId;
  Future<String?>? _starting;

  /// Changes on every start and stop, so work of an older capture stops.
  var _generation = 0;

  PhoenixChannelsClient? _channel;
  String? _topic;
  var _ready = false;
  var _joinedOnce = false;
  var _queue = <Map<String, Object?>>[];
  var _dropped = 0;
  Timer? _timer;
  Future<void>? _inFlight;
  final _linkedThreads = <String>{};

  /// The trajectory being captured or started, or `null`.
  String? get trajectoryId => _trajectoryId;

  /// Whether events are being captured: the channel is joined.
  bool get isCapturing => _ready;

  /// Starts capturing the trajectory [trajectoryId], a UUID, or a new one.
  ///
  /// Completes with the id once the channel is joined, or with `null` when
  /// the capture failed (the error went to the handler) or was stopped
  /// first. Starting the trajectory that is already started, or starting
  /// without an id while one is, returns the same future. Starting another
  /// one stops the current one first.
  Future<String?> start({String? trajectoryId}) {
    final current = _trajectoryId;
    if (current != null && (trajectoryId == null || trajectoryId == current)) {
      return _starting!;
    }
    final stopping = current == null ? Future<void>.value() : stop();
    final id = trajectoryId ?? _uuid.v4();
    _trajectoryId = id;
    final generation = ++_generation;
    return _starting = stopping.then(
      (_) => generation == _generation ? _connect(id, generation) : null,
    );
  }

  /// Captures the developer event [name] with [value], e.g. an outcome like
  /// `deal.approved`.
  ///
  /// [value] must be JSON: an object's fields are kept next to `seq`,
  /// anything else is sent as `data`. A name that is empty, longer than 200
  /// characters, has a NUL or is a [TrajectoryBuiltInEvent] reports
  /// `INVALID_EVENT` instead. Nothing is captured before [start] has joined.
  void emit(String name, Object? value) {
    if (name.trim().isEmpty ||
        name.length > 200 ||
        name.contains('\u0000') ||
        TrajectoryBuiltInEvent.isReserved(name)) {
      return _report('INVALID_EVENT', 'The event name "$name" is not allowed.');
    }
    _capture(name, value);
  }

  /// Captures the built-in [event] with [value], as the SDK's own collectors
  /// do.
  void record(TrajectoryBuiltInEvent event, Map<String, Object?> value) =>
      _capture(event.wireName, value);

  /// Captures `thread.linked` for [threadId], once per thread while the
  /// connection lasts.
  void linkThread(String threadId) {
    if (!_ready || !_linkedThreads.add(threadId)) return;
    record(TrajectoryBuiltInEvent.threadLinked, {'threadId': threadId});
  }

  /// Sends what is queued, then stops capturing and closes the channel.
  ///
  /// Events still queued after the last batch are reported as
  /// `EVENTS_DROPPED`. Does nothing when nothing was started.
  Future<void> stop() async {
    if (_trajectoryId == null) return;
    final generation = ++_generation;
    if (_ready) {
      _flush();
      await _inFlight;
      _flush();
      await _inFlight;
    }
    final lost = _queue.length + _dropped;
    if (lost > 0) _report('EVENTS_DROPPED', '$lost events were not sent.');
    await _end();
    // A start made meanwhile owns the state now.
    if (generation != _generation) return;
    _trajectoryId = null;
    _starting = null;
    _joinedOnce = false;
  }

  Future<String?> _connect(String id, int generation) async {
    var attempt = 0;
    while (true) {
      try {
        final grant = await _client.connect(id);
        if (generation != _generation) return null;
        await _join(grant, generation);
        if (generation != _generation) return null;
        _joinedOnce = true;
        _ready = true;
        // What was lost while disconnected goes out at once.
        if (_dropped > 0) _flush();
        return id;
      } on TrajectoryException catch (error) {
        if (generation != _generation) return null;
        _reportError(error);
        await _end();
        if (!_joinedOnce || !error.isRetryable) {
          // A capture that never started, or a refusal, ends here.
          if (generation == _generation) {
            _trajectoryId = null;
            _starting = null;
            _joinedOnce = false;
          }
          return null;
        }
        await Future<void>.delayed(_reconnectDelay(++attempt));
        if (generation != _generation) return null;
      }
    }
  }

  /// Opens a socket for [grant] and joins its channel, or throws a
  /// [TrajectoryException].
  Future<void> _join(TrajectoryGrant grant, int generation) async {
    final channel = _channelFactory(grant.clientUrl, {
      'join_token': grant.joinToken,
    });
    _channel = channel;
    _topic = grant.topic;
    // Listen before opening: early frames are lost otherwise.
    channel.events.listen(
      (_) {},
      onError: (Object error) => _onLost(channel, generation),
      onDone: () => _onLost(channel, generation),
    );
    try {
      await channel.open();
      await channel.join(grant.topic, const {});
    } on PhoenixReplyException catch (error) {
      final reason = switch (error.response) {
        {'reason': final String reason} => reason,
        _ => null,
      };
      throw TrajectoryException(
        code: _joinRefusals[reason] ?? 'JOIN_FAILED',
        message: 'The trajectory channel refused the join: $reason',
        isRetryable: true,
      );
    } on TimeoutException {
      throw const TrajectoryException(
        code: 'CONNECTION_TIMEOUT',
        message: 'The trajectory channel did not answer the join.',
        isRetryable: true,
      );
    } on Object catch (error) {
      throw TrajectoryException(
        code: 'CONNECTION_LOST',
        message: 'The trajectory socket failed: $error',
        isRetryable: true,
      );
    }
  }

  /// The socket of [channel] ended while it was the current one: count what
  /// was queued as dropped and reconnect with a new grant.
  void _onLost(PhoenixChannelsClient channel, int generation) {
    if (generation != _generation || !identical(channel, _channel)) return;
    if (!_ready) return;
    _ready = false;
    _channel = null;
    _timer?.cancel();
    _timer = null;
    _dropped += _queue.length;
    _queue = [];
    _linkedThreads.clear();
    _report('CONNECTION_LOST', 'The trajectory socket closed.');
    final id = _trajectoryId!;
    _starting = Future<void>.delayed(
      _reconnectDelay(1),
    ).then((_) => generation == _generation ? _connect(id, generation) : null);
  }

  void _capture(String name, Object? value) {
    if (!_ready) {
      // Lost while reconnecting; nothing is captured before the first join.
      if (_joinedOnce) _dropped++;
      return;
    }
    final seq = _nextSeq ??= _clock() * 1000;
    if (seq > _maxSafeInteger) {
      _dropped++;
      return _report('SEQUENCE_EXHAUSTED', 'No sequence number is left.');
    }
    _nextSeq = seq + 1;
    final Map<String, Object?> wire;
    final int size;
    try {
      wire = {
        'type': 'CUSTOM',
        'name': name,
        'timestamp': _clock(),
        'value': switch (value) {
          final Map<String, Object?> fields when !fields.containsKey('seq') => {
            ...fields,
            'seq': seq,
          },
          _ => {'data': value, 'seq': seq},
        },
      };
      size = utf8.encode(jsonEncode(wire)).length;
    } on Object catch (error) {
      _dropped++;
      return _report('INVALID_EVENT', 'The event "$name" is not JSON: $error');
    }
    if (size > _maxEventBytes) {
      _dropped++;
      return _report(
        'EVENT_TOO_LARGE',
        'The event "$name" is $size bytes, over $_maxEventBytes.',
      );
    }
    if (!_fits(wire)) _flush();
    if (!_fits(wire)) {
      _dropped++;
      return _report('EVENTS_DROPPED', 'The event "$name" fits no batch.');
    }
    _queue.add(wire);
    if (_queue.length >= _maxBatchEvents) {
      _flush();
    } else {
      _timer ??= Timer(_batchInterval, _flush);
    }
  }

  /// Whether the queue with [wire] added stays within a batch.
  bool _fits(Map<String, Object?> wire) =>
      utf8
          .encode(
            jsonEncode({
              'events': [..._queue, wire],
              'dropped': _maxSafeInteger,
            }),
          )
          .length <=
      _maxBatchBytes;

  /// Sends the queue and the dropped count as one batch, unless a batch is
  /// on its way or there is nothing to send.
  void _flush() {
    _timer?.cancel();
    _timer = null;
    final channel = _channel;
    final topic = _topic;
    if (_inFlight != null || !_ready || channel == null || topic == null) {
      return;
    }
    if (_queue.isEmpty && _dropped == 0) return;
    final batch = _queue;
    final dropped = _dropped;
    _queue = [];
    _dropped = 0;
    _inFlight = _send(channel, topic, batch, dropped).whenComplete(() {
      _inFlight = null;
      if (_ready && (_queue.isNotEmpty || _dropped > 0)) _flush();
    });
  }

  Future<void> _send(
    PhoenixChannelsClient channel,
    String topic,
    List<Map<String, Object?>> batch,
    int dropped,
  ) async {
    try {
      final reply = await channel.push(topic, 'events', {
        'events': batch,
        'dropped': dropped,
      });
      final receipt = TrajectoryReceipt.tryParse(reply, batch.length);
      if (receipt == null) {
        _report('PERSISTENCE_UNKNOWN', 'The batch got an invalid receipt.');
      } else if (receipt.rejected > 0) {
        _report(
          'EVENTS_REJECTED',
          '${receipt.rejected} of ${batch.length} events were rejected.',
        );
      }
    } on PhoenixReplyException catch (error) {
      final reason = switch (error.response) {
        {'reason': final String reason} => reason,
        _ => null,
      };
      if (reason == 'unauthorized' || reason == 'trajectory_mismatch') {
        _dropped += batch.length + dropped;
        _reportError(
          TrajectoryException(
            code: reason!.toUpperCase(),
            message: 'The trajectory channel refused the batch: $reason',
          ),
        );
        // A refusal ends the capture.
        _generation++;
        _ready = false;
        unawaited(_end());
        _trajectoryId = null;
        _starting = null;
        _joinedOnce = false;
      } else if (_rollbackReasons.contains(reason)) {
        _dropped += batch.length + dropped;
        _report(reason!.toUpperCase(), 'The batch was refused: $reason');
      } else {
        _report('PERSISTENCE_UNKNOWN', 'The batch was refused: $reason');
      }
    } on Object catch (error) {
      _report('PERSISTENCE_UNKNOWN', 'The batch got no receipt: $error');
    }
  }

  /// Closes the current socket, if any, and forgets what was queued.
  Future<void> _end() async {
    _ready = false;
    _timer?.cancel();
    _timer = null;
    _queue = [];
    _dropped = 0;
    _linkedThreads.clear();
    final channel = _channel;
    _channel = null;
    _topic = null;
    await channel?.close();
  }

  void _report(String code, String message) =>
      _reportError(TrajectoryException(code: code, message: message));

  void _reportError(TrajectoryException error) {
    final onError = _onError;
    if (onError != null) return onError(error);
    developer.log(
      error.toString(),
      name: 'copilotkit.trajectory',
      level: 900, // WARNING
    );
  }

  static Duration _defaultReconnectDelay(int attempt) => Duration(
    milliseconds: math.min(1000 * math.pow(2, attempt - 1), 10000).toInt(),
  );
}
