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
  /// The replay is always a full one: the runtime is asked for no cursor. It
  /// ends when the gateway has sent both `replay_complete` and `stream_idle`,
  /// not on `RUN_FINISHED`: a replay may hold a run without its end, and
  /// nothing follows once the stream is idle. The events are passed on as the
  /// gateway sent them, as `@copilotkit/core` does: a run left open is not
  /// closed here. A `204` means the runtime has no history for the thread, and
  /// the stream is empty. A channel that closes before the replay ends is
  /// replayed again from the last event seen (the `cpki_event_id` of its
  /// metadata), up to `maxReconnects` times, and is an error after that.
  /// Failing to get credentials is an error at once.
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
        start(
          controller,
          end,
          (opened) => channel = opened,
          (listening) => subscription = listening,
        ),
      ),
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
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
    try {
      while (true) {
        final dropped = await _connectOnce(
          agentId: agentId,
          input: input,
          headers: headers,
          cursor: cursor,
          controller: controller,
          onCursor: (id) => cursor = id,
          onChannel: onChannel,
          onSubscription: onSubscription,
        );
        if (dropped == null || _closed || controller.isClosed) break;
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

  /// One attempt at the replay, from [cursor]. Returns `null` when the replay
  /// ended, or why the channel dropped before it did.
  Future<_Drop?> _connectOnce({
    required String agentId,
    required RunAgentInput input,
    required Map<String, String> headers,
    required String? cursor,
    required StreamController<BaseEvent> controller,
    required void Function(String? id) onCursor,
    required void Function(PhoenixChannelsClient channel) onChannel,
    required void Function(StreamSubscription<PhoenixEvent> subscription)
    onSubscription,
  }) async {
    final credentials = await _requestConnect(agentId, input, headers, cursor);
    // Closed or cancelled while the runtime was answering: don't join.
    if (_closed || controller.isClosed) return null;
    // No history for the thread.
    if (credentials == null) return null;
    final channel = _channelFactory(Uri.parse(credentials.realtime.clientUrl), {
      'join_token': credentials.joinToken,
    });
    onChannel(channel);
    var replayComplete = false;
    var streamIdle = false;
    final outcome = Completer<_Drop?>();
    void settle(_Drop? value) {
      if (!outcome.isCompleted) outcome.complete(value);
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
              return _reportSkipped(error, stackTrace);
            }
            controller.add(event);
            onCursor(_cursorOf(frame.payload) ?? cursor);
          case 'replay_complete':
            replayComplete = true;
          case 'stream_idle':
            streamIdle = true;
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
    // A channel that can't be opened or joined is an error, not a drop: the
    // runtime refused it, and asking again would be refused again.
    await channel.open();
    await channel.join(credentials.realtime.topic, {
      'stream_mode': 'connect',
      'last_seen_event_id': cursor,
    });
    return await outcome.future;
  }

  Future<void> _release(
    StreamSubscription<PhoenixEvent> subscription,
    PhoenixChannelsClient channel,
  ) async {
    await subscription.cancel();
    await _closeChannel(channel);
  }

  /// The id of the event in an `ag_ui_event` payload, if the gateway gave one.
  String? _cursorOf(Map<String, Object?> payload) =>
      switch (payload['metadata']) {
        {'cpki_event_id': final String id} => id,
        _ => null,
      };

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
      throw http.ClientException(
        '$what failed with status ${response.statusCode}: ${response.body}',
        url,
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
