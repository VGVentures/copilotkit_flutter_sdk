// cspell:ignore realtime
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:copilotkit/src/transport/intelligence_event_decoder.dart';
import 'package:copilotkit/src/transport/models/intelligence_connect_credentials.dart';
import 'package:copilotkit/src/transport/models/intelligence_run_credentials.dart';
import 'package:copilotkit/src/transport/models/runtime_info.dart';
import 'package:copilotkit/src/transport/models/stop_request.dart';
import 'package:copilotkit/src/transport/models/thread_locked_exception.dart';
import 'package:copilotkit/src/transport/runtime_info_client.dart';
import 'package:copilotkit/src/transport/simple_input_mapper.dart';
import 'package:http/http.dart' as http;
import 'package:json_annotation/json_annotation.dart';
import 'package:phoenix_channels_client/phoenix_channels_client.dart';

/// [AgentTransport] over a Copilot Runtime with Intelligence turned on.
///
/// Such a runtime doesn't stream a run. `POST /agent/{id}/run` answers with
/// the credentials of the run, and its AG-UI events arrive as `ag_ui_event`
/// frames on a Phoenix channel. Every run joins its own channel, which is
/// closed when the run ends or its subscription is cancelled.
///
/// [connect] replays a thread the same way: `POST /agent/{id}/connect` answers
/// with credentials, and the replay arrives on a channel joined in `connect`
/// mode.
///
/// A run doesn't reconnect: a connection that drops ends it with the error
/// that dropped it. The join token is single-use, so a reconnect needs fresh
/// credentials (see ADR 0012). [connect] does reconnect: a replay whose channel
/// drops starts again with new credentials, from the last event it saw, a
/// limited number of times with a growing wait.
///
/// A thread that already has a run answers `409`, which this transport
/// throws as a [ThreadLockedException].
///
/// This class is mutable: it tracks the runs in flight.
class IntelligenceTransport({
  required Uri runtimeUrl,
  http.Client Function()? httpClientFactory,
  PhoenixChannelsClient Function(Uri clientUrl, Map<String, String> params)?
  channelFactory,
  Duration stopTimeout = const Duration(seconds: 10),
  int maxReconnects = 5,
  Duration Function(int attempt)? reconnectDelay,
  Duration idleFallback = const Duration(milliseconds: 100),
  Duration idleWarning = const Duration(seconds: 30),
  void Function(Object error, StackTrace stackTrace)? onSkippedEvent,
  IntelligenceEventDecoder decoder = const IntelligenceEventDecoder(),
  SimpleInputMapper simpleInput = const SimpleInputMapper(),
}) implements AgentTransport {
  /// Creates a transport for the runtime at [runtimeUrl].
  ///
  /// [httpClientFactory] creates the client of each request; defaults to
  /// [http.Client.new].
  ///
  /// [channelFactory] creates the Phoenix client of each run from the socket
  /// URL and its handshake parameters; tests pass a fake.
  ///
  /// [stopTimeout] bounds the stop request, so a hung runtime can't hang
  /// `stop`.
  ///
  /// [maxReconnects] is how many times [connect] asks for a new replay when
  /// its channel drops before the replay ends, and [reconnectDelay] gives the
  /// wait before attempt `attempt` (from 1); it defaults to a doubling wait
  /// from 100 ms up to 10 s, as `@copilotkit/core` waits.
  ///
  /// [idleFallback] is how long [connect] waits, after a `stream_idle` that
  /// came without `replay_complete`, before it ends the replay anyway; and
  /// [idleWarning] is how long a replay that has sent `replay_complete` may be
  /// silent before a warning is logged. Both are `@copilotkit/core`'s values.
  ///
  /// [onSkippedEvent] is called with each event the transport skipped because
  /// it couldn't be decoded. Errors it throws are logged and don't end the
  /// run.
  this;

  final String _baseUrl = runtimeUrl.toString().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  final http.Client Function() _httpClientFactory =
      httpClientFactory ?? http.Client.new;
  final PhoenixChannelsClient Function(Uri, Map<String, String>)
  _channelFactory =
      channelFactory ??
      ((clientUrl, params) =>
          PhoenixChannelsClient(clientUrl: clientUrl, params: params));
  final Duration _stopTimeout = stopTimeout;
  final int _maxReconnects = maxReconnects;
  final Duration _idleFallback = idleFallback;
  final Duration _idleWarning = idleWarning;
  final Duration Function(int attempt) _reconnectDelay =
      reconnectDelay ?? _defaultReconnectDelay;
  late final RuntimeInfoClient _info = RuntimeInfoClient(
    baseUrl: _baseUrl,
    httpClientFactory: _httpClientFactory,
    timeout: _stopTimeout,
  );
  final void Function(Object error, StackTrace stackTrace)? _onSkippedEvent =
      onSkippedEvent;
  final IntelligenceEventDecoder _decoder = decoder;
  final SimpleInputMapper _simpleInput = simpleInput;

  /// Ends each run in flight, see [close].
  final Set<void Function()> _runEnds = {};

  /// The credentials the runtime gave each run, by the run id the app asked
  /// for, so [stop] uses the runtime's own ids.
  final Map<String, IntelligenceRunCredentials> _credentials = {};
  bool _closed = false;

  /// Replays the thread of [input], and streams the events of a run of it that
  /// is still going.
  ///
  /// The first attempt asks the runtime for a full replay: it sends no cursor.
  /// The replay ends when the gateway has sent both `replay_complete` and
  /// `stream_idle`, not on `RUN_FINISHED`: a replay may hold a run without its
  /// end, and nothing follows once the stream is idle. The events are passed
  /// on as the gateway sent them, as `@copilotkit/core` does: a run left open
  /// is not closed here. A `204` means the runtime has no history for the
  /// thread, and the stream is empty.
  ///
  /// A channel that closes or fails before the replay ends is replayed again
  /// from the last event seen (the `cpki_event_id` of its metadata), waiting
  /// longer each time. Once a replay has got going, a network that is still
  /// down when it tries again, or a gateway that answers `5xx`, `408` or
  /// `429`, counts as another drop. An attempt that delivered new events
  /// starts the count over; after `maxReconnects` drops in a row the last one
  /// is an error. Failing to get the first credentials, or a request or join
  /// the runtime refuses, is an error at once.
  ///
  /// A `stream_idle` without `replay_complete` ends the replay after a short
  /// wait (`idleFallback`), when the idle's `latestEventId` is the cursor the
  /// attempt started from or the last event it saw, or when it names none.
  /// A gateway that sends `replay_complete` but never `stream_idle` keeps the
  /// stream open for as long as the socket lives, and the agent stays running:
  /// a run still going on the thread legitimately does the same, so there is
  /// no limit. After `idleWarning` of silence a warning is logged, as
  /// `@copilotkit/core` does. Cancel the stream to end it.
  @override
  Stream<BaseEvent> connect({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) => _open(
    (controller, end, onChannel, onSubscription) => _startConnect(
      agentId: agentId,
      input: input,
      headers: headers,
      controller: controller,
      end: end,
      onChannel: onChannel,
      onSubscription: onSubscription,
    ),
  );

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) => _open(
    (controller, end, onChannel, onSubscription) => _start(
      agentId: agentId,
      input: input,
      headers: headers,
      controller: controller,
      end: end,
      onChannel: onChannel,
      onSubscription: onSubscription,
    ),
  );

  /// Asks the runtime to stop the run, with the ids it gave that run.
  ///
  /// Throws a [ThreadLockedException] on `409`, and an [http.ClientException]
  /// when the runtime rejects the request or doesn't answer within the stop
  /// timeout.
  @override
  Future<void> stop({
    required String agentId,
    required String threadId,
    required String runId,
    Map<String, String> headers = const {},
  }) async {
    _ensureOpen();
    final credentials = _credentials[runId];
    final url = Uri.parse(
      '$_baseUrl/agent/${Uri.encodeComponent(agentId)}'
      '/stop/${Uri.encodeComponent(credentials?.threadId ?? threadId)}',
    );
    final httpClient = _httpClientFactory();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode(StopRequest(runId: credentials?.runId ?? runId));
      final response = await _send(httpClient, request).timeout(_stopTimeout);
      _ensureSuccess(response, url, 'Stop');
    } on TimeoutException {
      throw http.ClientException(
        'Stop timed out after ${_stopTimeout.inMilliseconds}ms.',
        url,
      );
    } finally {
      httpClient.close();
    }
  }

  /// Reads the runtime's `GET /info`.
  ///
  /// Throws an [http.ClientException] when the runtime rejects the request,
  /// doesn't answer within the stop timeout or doesn't answer with a JSON
  /// object.
  @override
  Future<RuntimeInfo> info({Map<String, String> headers = const {}}) async {
    _ensureOpen();
    return await _info(headers: headers);
  }

  /// Ends the runs in flight (their streams complete). The transport can't be
  /// used afterwards.
  @override
  Future<void> close() async {
    _closed = true;
    for (final end in [..._runEnds]) {
      end();
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('IntelligenceTransport is closed.');
  }

  /// Streams what [start] puts into the stream it is given, and ends it once,
  /// however it ends: finished, failed, cancelled or closed. Ending closes the
  /// channel, which closes the socket.
  Stream<BaseEvent> _open(
    Future<void> Function(
      StreamController<BaseEvent> controller,
      void Function() end,
      void Function(PhoenixChannelsClient channel) onChannel,
      void Function(StreamSubscription<PhoenixEvent> subscription)
      onSubscription,
    )
    start,
  ) {
    _ensureOpen();
    PhoenixChannelsClient? channel;
    StreamSubscription<PhoenixEvent>? subscription;
    // The listener's pause outlives the subscription: a reconnect hands over
    // a new one, which must start paused too.
    var paused = false;
    late final StreamController<BaseEvent> controller;
    late final void Function() end;
    end = () {
      if (!_runEnds.remove(end)) return;
      unawaited(subscription?.cancel());
      unawaited(_closeChannel(channel));
      unawaited(controller.close());
    };
    _runEnds.add(end);
    controller = StreamController<BaseEvent>(
      onListen: () => unawaited(
        start(controller, end, (opened) => channel = opened, (listening) {
          subscription = listening;
          if (paused) listening.pause();
        }),
      ),
      onPause: () {
        paused = true;
        subscription?.pause();
      },
      onResume: () {
        paused = false;
        subscription?.resume();
      },
      onCancel: end,
    );
    return controller.stream;
  }

  /// Starts the run, joins its channel and streams its events into
  /// [controller]. Any failure is reported as an error of the stream and ends
  /// the run.
  Future<void> _start({
    required String agentId,
    required RunAgentInput input,
    required Map<String, String> headers,
    required StreamController<BaseEvent> controller,
    required void Function() end,
    required void Function(PhoenixChannelsClient channel) onChannel,
    required void Function(StreamSubscription<PhoenixEvent> subscription)
    onSubscription,
  }) async {
    // Closed before anyone listened: send nothing.
    if (_closed) return;
    try {
      final credentials = await _requestRun(agentId, input, headers);
      // Closed or cancelled while the runtime was answering: don't join.
      if (_closed || controller.isClosed) return;
      _credentials[input.runId] = credentials;
      final channel = _channelFactory(
        Uri.parse(credentials.realtime.clientUrl),
        {'join_token': credentials.joinToken},
      );
      onChannel(channel);
      // Listen before opening: early frames are lost otherwise.
      onSubscription(
        channel.events.listen(
          (event) => _onEvent(event, controller, end),
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
            end();
          },
          onDone: end,
        ),
      );
      await channel.open();
      await channel.join(credentials.realtime.topic, const {});
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
      end();
    }
  }

  /// Asks for the replay of the thread, joins its channel and streams the
  /// replay into [controller], asking again when the channel drops. Any other
  /// failure is reported as an error of the stream and ends it.
  Future<void> _startConnect({
    required String agentId,
    required RunAgentInput input,
    required Map<String, String> headers,
    required StreamController<BaseEvent> controller,
    required void Function() end,
    required void Function(PhoenixChannelsClient channel) onChannel,
    required void Function(StreamSubscription<PhoenixEvent> subscription)
    onSubscription,
  }) async {
    // Closed before anyone listened: send nothing.
    if (_closed) return;
    // The id of the last event passed on: where a new replay starts from.
    String? cursor;
    var reconnects = 0;
    // Whether a replay got going: from then on a transport failure is one more
    // drop to recover from. Before, it is an error at once.
    var joined = false;
    try {
      while (true) {
        final before = cursor;
        final dropped = await _connectOnce(
          agentId: agentId,
          input: input,
          headers: headers,
          cursor: cursor,
          controller: controller,
          // From the second attempt on, a transport failure is a drop to
          // recover from, not an error.
          recovering: joined,
          onCursor: (id) => cursor = id,
          onJoined: () => joined = true,
          onChannel: onChannel,
          onSubscription: onSubscription,
        );
        if (dropped == null || _closed || controller.isClosed) break;
        // An attempt that delivered events made progress: it starts the
        // budget and the wait over.
        if (cursor != before) reconnects = 0;
        if (++reconnects > _maxReconnects) {
          controller.addError(dropped.error, dropped.stackTrace);
          break;
        }
        // The next attempt has a channel of its own.
        await dropped.close();
        await Future<void>.delayed(_reconnectDelay(reconnects));
        if (_closed || controller.isClosed) break;
      }
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
    }
    end();
  }

  /// Whether [error] says the network or the gateway is unavailable, as
  /// opposed to refusing the request.
  bool _isTransient(Object error) => switch (error) {
    _StatusException(:final statusCode) =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429,
    http.ClientException() ||
    TimeoutException() ||
    PhoenixClosedException() => true,
    _ => false,
  };

  /// One attempt at the replay, from [cursor]. Returns `null` when the replay
  /// ended, or why the channel dropped before it did.
  Future<_Drop?> _connectOnce({
    required String agentId,
    required RunAgentInput input,
    required Map<String, String> headers,
    required String? cursor,
    required StreamController<BaseEvent> controller,
    required bool recovering,
    required void Function(String? id) onCursor,
    required void Function() onJoined,
    required void Function(PhoenixChannelsClient channel) onChannel,
    required void Function(StreamSubscription<PhoenixEvent> subscription)
    onSubscription,
  }) async {
    final IntelligenceConnectCredentials? credentials;
    try {
      credentials = await _requestConnect(agentId, input, headers, cursor);
    } on Object catch (error, stackTrace) {
      // A network that is still down, or a gateway that is unavailable: a
      // refusal (a 4xx) is an error, and asking again would be refused again.
      if (recovering && _isTransient(error)) return _dropOf(error, stackTrace);
      rethrow;
    }
    // Closed or cancelled while the runtime was answering: don't join.
    if (_closed || controller.isClosed) return null;
    // No history for the thread.
    if (credentials == null) return null;
    final granted = credentials;
    final channel = _channelFactory(Uri.parse(granted.realtime.clientUrl), {
      'join_token': granted.joinToken,
    });
    onChannel(channel);
    if (granted.threadId != input.threadId) {
      developer.log(
        'The runtime replays thread ${granted.threadId} for '
        '${input.threadId}; the agent keeps the id it was given.',
        name: 'copilotkit',
        level: 900, // WARNING
      );
    }
    var replayComplete = false;
    var streamIdle = false;
    // The last event this attempt saw, to tell whether a `stream_idle` is the
    // one that belongs to it.
    var lastSeen = cursor;
    Timer? fallback;
    Timer? warning;
    final outcome = Completer<_Drop?>();
    void settle(_Drop? value) {
      fallback?.cancel();
      warning?.cancel();
      if (!outcome.isCompleted) outcome.complete(value);
    }

    void armWarning() {
      warning?.cancel();
      if (!replayComplete || outcome.isCompleted) return;
      warning = Timer(
        _idleWarning,
        () => developer.log(
          'No progress or stream_idle for ${_idleWarning.inSeconds} seconds '
          'after replay_complete: the run may still be active or its status '
          'unavailable.',
          name: 'copilotkit',
          level: 900, // WARNING
        ),
      );
    }

    // Listen before opening: early frames are lost otherwise.
    late final StreamSubscription<PhoenixEvent> subscription;
    subscription = channel.events.listen(
      (frame) {
        if (controller.isClosed) return;
        switch (frame.event) {
          case 'ag_ui_event':
            final BaseEvent event;
            try {
              event = _decoder(frame.payload);
            } on DecodingError catch (error, stackTrace) {
              // Dealt with: a new replay must not start before it.
              lastSeen = _cursorOf(frame.payload) ?? lastSeen;
              onCursor(lastSeen);
              return _reportSkipped(error, stackTrace);
            }
            controller.add(event);
            lastSeen = _cursorOf(frame.payload) ?? lastSeen;
            onCursor(lastSeen);
            armWarning();
          case 'replay_complete':
            replayComplete = true;
            armWarning();
          case 'stream_idle':
            streamIdle = true;
            // Without replay_complete, the idle may still end the replay: core
            // completes after a short wait when it is this attempt's idle.
            final idleId = _controlIdOf(frame.payload);
            if (!replayComplete &&
                (idleId == null || idleId == cursor || idleId == lastSeen)) {
              fallback = Timer(_idleFallback, () {
                if (!replayComplete) settle(null);
              });
            }
        }
        if (replayComplete && streamIdle) settle(null);
      },
      onError: (Object error, StackTrace stackTrace) => settle((
        error: error,
        stackTrace: stackTrace,
        close: () => _release(subscription, channel),
      )),
      onDone: () => settle((
        error: StateError('The connection closed before the replay finished.'),
        stackTrace: StackTrace.current,
        close: () => _release(subscription, channel),
      )),
    );
    onSubscription(subscription);
    // Set up beside the outcome, not before it: a channel that drops while it
    // is being joined is a drop, and a join that never answers must not hang
    // the attempt. A channel the runtime refuses is an error, not a drop.
    final refused = Completer<void>();
    unawaited(() async {
      try {
        await channel.open();
        await channel.join(granted.realtime.topic, {
          'stream_mode': 'connect',
          'last_seen_event_id': cursor,
        });
        onJoined();
      } on Object catch (error, stackTrace) {
        if (!outcome.isCompleted) refused.completeError(error, stackTrace);
      }
    }());
    try {
      return await Future.any<_Drop?>([
        outcome.future,
        refused.future.then<_Drop?>((_) => null),
      ]);
    } on Object catch (error, stackTrace) {
      if (!recovering || !_isTransient(error)) rethrow;
      await _release(subscription, channel);
      return _dropOf(error, stackTrace);
    }
  }

  _Drop _dropOf(Object error, StackTrace stackTrace) =>
      (error: error, stackTrace: stackTrace, close: () async {});

  Future<void> _release(
    StreamSubscription<PhoenixEvent> subscription,
    PhoenixChannelsClient channel,
  ) async {
    await subscription.cancel();
    await _closeChannel(channel);
  }

  /// The id of the event in an `ag_ui_event` payload, if the gateway gave one
  /// that a replay can resume from.
  String? _cursorOf(Map<String, Object?> payload) =>
      switch (payload['metadata']) {
        {'cpki_event_id': final Object? id} => _durable(id),
        _ => null,
      };

  /// The id of the latest event a control frame (`replay_complete`,
  /// `stream_idle`) names, if it names a durable one.
  String? _controlIdOf(Map<String, Object?> payload) =>
      _durable(payload['latestEventId'] ?? payload['latest_event_id']);

  /// [id] if it is an event id a replay can resume from. An id that starts
  /// with `cpki_ingested` marks an event not stored yet, as in
  /// `@copilotkit/core`.
  String? _durable(Object? id) =>
      id is String && id.trim().isNotEmpty && !id.startsWith('cpki_ingested')
      ? id
      : null;

  /// Asks the runtime for the replay of the thread of [input], or returns
  /// `null` when it has no history for it (`204`).
  Future<IntelligenceConnectCredentials?> _requestConnect(
    String agentId,
    RunAgentInput input,
    Map<String, String> headers,
    String? cursor,
  ) async {
    final url = Uri.parse(
      '$_baseUrl/agent/${Uri.encodeComponent(agentId)}/connect',
    );
    final httpClient = _httpClientFactory();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        // No cursor for the first attempt: the agent was cleared, so the
        // replay must be a full one.
        ..body = jsonEncode({
          ..._simpleInput(input).toJson(),
          'lastSeenEventId': cursor,
        });
      final response = await _send(httpClient, request);
      if (response.statusCode == 204) return null;
      _ensureSuccess(response, url, 'Connect');
      final credentials = _credentialsOf(
        response,
        'connect credentials',
        IntelligenceConnectCredentials.fromJson,
      );
      return credentials;
    } finally {
      httpClient.close();
    }
  }

  Future<IntelligenceRunCredentials> _requestRun(
    String agentId,
    RunAgentInput input,
    Map<String, String> headers,
  ) async {
    final url = Uri.parse(
      '$_baseUrl/agent/${Uri.encodeComponent(agentId)}/run',
    );
    final httpClient = _httpClientFactory();
    try {
      final request = http.Request('POST', url)
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode(_simpleInput(input).toJson());
      final response = await _send(httpClient, request);
      _ensureSuccess(response, url, 'Run');
      final credentials = _credentialsOf(
        response,
        'run credentials',
        IntelligenceRunCredentials.fromJson,
      );
      return credentials;
    } finally {
      httpClient.close();
    }
  }

  /// Decodes the body of [response] with [fromJson]. Throws a
  /// [FormatException] naming [what] when it isn't a JSON object of that
  /// shape.
  T _credentialsOf<T>(
    http.Response response,
    String what,
    T Function(Map<String, Object?> json) fromJson,
  ) {
    final json = jsonDecode(response.body);
    if (json is! Map<String, Object?>) {
      throw FormatException(
        'The runtime did not answer with $what.',
        response.body,
      );
    }
    try {
      return fromJson(json);
    } on CheckedFromJsonException catch (error) {
      throw FormatException(
        'The runtime did not answer with $what: ${error.message}',
        response.body,
      );
    }
  }

  /// Throws when [response] isn't a success: a [ThreadLockedException] for
  /// `409`, an [http.ClientException] otherwise.
  void _ensureSuccess(http.Response response, Uri url, String what) {
    if (response.statusCode == 409) {
      throw ThreadLockedException(message: _errorOf(response.body));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _StatusException(
        '$what failed with status ${response.statusCode}: ${response.body}',
        url,
        response.statusCode,
      );
    }
  }

  /// The `error` the runtime put in a JSON body, if it did.
  String? _errorOf(String body) {
    try {
      if (jsonDecode(body) case {'error': final String error}) return error;
    } on FormatException {
      // Not JSON: there is no message to give.
    }
    return null;
  }

  void _onEvent(
    PhoenixEvent frame,
    StreamController<BaseEvent> controller,
    void Function() end,
  ) {
    if (frame.event != 'ag_ui_event' || controller.isClosed) return;
    final BaseEvent event;
    try {
      event = _decoder(frame.payload);
    } on DecodingError catch (error, stackTrace) {
      return _reportSkipped(error, stackTrace);
    }
    controller.add(event);
    if (event is RunFinishedEvent || event is RunErrorEvent) end();
  }

  /// Logs an event skipped because it couldn't be decoded and reports it to
  /// `onSkippedEvent`, which must not break the run if it throws.
  void _reportSkipped(Object error, StackTrace stackTrace) {
    developer.log(
      'Skipped undecodable AG-UI event: $error',
      name: 'copilotkit',
    );
    try {
      _onSkippedEvent?.call(error, stackTrace);
    } on Object catch (callbackError, callbackStackTrace) {
      developer.log(
        'onSkippedEvent threw',
        name: 'copilotkit',
        level: 1000, // SEVERE
        error: callbackError,
        stackTrace: callbackStackTrace,
      );
    }
  }

  Future<http.Response> _send(http.Client client, http.Request request) async {
    final streamed = await client.send(request);
    return await http.Response.fromStream(streamed);
  }

  /// Closes [channel], ignoring errors from a socket that is already being
  /// torn down.
  Future<void> _closeChannel(PhoenixChannelsClient? channel) async {
    try {
      await channel?.close();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Closing the channel failed',
        name: 'copilotkit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Doubles from 100 ms and stops at 10 s.
  static Duration _defaultReconnectDelay(int attempt) {
    final milliseconds = 100 * (1 << (attempt - 1).clamp(0, 10));
    return Duration(milliseconds: milliseconds.clamp(100, 10000));
  }
}

/// Why a replay's channel dropped, and how to let go of it.
typedef _Drop = ({
  Object error,
  StackTrace stackTrace,
  Future<void> Function() close,
});

/// A request the runtime answered with a status that is not a success.
class _StatusException extends http.ClientException {
  new(super.message, Uri super.uri, this.statusCode);

  final int statusCode;
}
