// cspell:ignore realtime
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/agent_transport.dart';
import 'package:copilotkit/src/transport/intelligence_event_decoder.dart';
import 'package:copilotkit/src/transport/models/intelligence_run_credentials.dart';
import 'package:copilotkit/src/transport/models/stop_request.dart';
import 'package:copilotkit/src/transport/models/thread_locked_exception.dart';
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
/// The transport doesn't reconnect: a connection that drops ends the run with
/// the error that dropped it. The join token is single-use, so a reconnect
/// needs fresh credentials (see ADR 0012).
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

  @override
  Stream<BaseEvent> run({
    required String agentId,
    required RunAgentInput input,
    Map<String, String> headers = const {},
  }) {
    _ensureOpen();
    PhoenixChannelsClient? channel;
    StreamSubscription<PhoenixEvent>? subscription;
    late final StreamController<BaseEvent> controller;
    // Ends the run once, however it ends: finished, failed, cancelled or
    // closed. Closing the channel closes the socket.
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
        _start(
          agentId: agentId,
          input: input,
          headers: headers,
          controller: controller,
          end: end,
          onChannel: (opened) => channel = opened,
          onSubscription: (listening) => subscription = listening,
        ),
      ),
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: end,
    );
    return controller.stream;
  }

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
      final json = jsonDecode(response.body);
      if (json is! Map<String, Object?>) {
        throw FormatException(
          'The runtime did not answer with run credentials.',
          response.body,
        );
      }
      try {
        return IntelligenceRunCredentials.fromJson(json);
      } on CheckedFromJsonException catch (error) {
        throw FormatException(
          'The runtime did not answer with run credentials: ${error.message}',
          response.body,
        );
      }
    } finally {
      httpClient.close();
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
}
