import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/ag_ui_transport.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client;

class _FakeBaseRequest extends Fake implements http.BaseRequest;

http.StreamedResponse _sse(Stream<List<int>> body, {int statusCode = 200}) {
  return http.StreamedResponse(
    body,
    statusCode,
    headers: {'content-type': 'text/event-stream'},
  );
}

List<int> _event(Map<String, Object?> json) =>
    utf8.encode('data: ${jsonEncode(json)}\n\n');

final _input = RunAgentInput(
  threadId: 'thread-1',
  runId: 'run-1',
  state: const {'count': 1},
  messages: [UserMessage(id: 'u1', content: 'Hi')],
  tools: const [],
  context: const [Context(description: 'User', value: '"Ada"')],
  forwardedProps: const {'userId': '42'},
);

void main() {
  setUpAll(() => registerFallbackValue(_FakeBaseRequest()));

  group(AgUiTransport, () {
    late _MockHttpClient httpClient;
    late AgUiTransport transport;

    setUp(() {
      httpClient = _MockHttpClient();
      transport = AgUiTransport(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        httpClientFactory: () => httpClient,
      );
    });

    void stubResponse(http.StreamedResponse response) {
      when(() => httpClient.send(any())).thenAnswer((_) async => response);
    }

    test('posts the input to the agent run route and decodes events', () async {
      stubResponse(
        _sse(
          Stream.fromIterable([
            _event({
              'type': 'RUN_STARTED',
              'threadId': 'thread-1',
              'runId': 'run-1',
            }),
            _event({
              'type': 'RUN_FINISHED',
              'threadId': 'thread-1',
              'runId': 'run-1',
            }),
          ]),
        ),
      );

      final events = await transport
          .run(
            agentId: 'default',
            input: _input,
            headers: {'Authorization': 'Bearer token'},
          )
          .toList();

      expect(events, [isA<RunStartedEvent>(), isA<RunFinishedEvent>()]);
      final request =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.Request;
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('http://runtime.test/api/copilotkit/agent/default/run'),
      );
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.headers['Accept'], contains('text/event-stream'));
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['threadId'], 'thread-1');
      expect(body['runId'], 'run-1');
      expect(body['state'], {'count': 1});
      expect(body['messages'], [
        {'id': 'u1', 'role': 'user', 'content': 'Hi'},
      ]);
      expect(body['context'], [
        {'description': 'User', 'value': '"Ada"'},
      ]);
      expect(body['forwardedProps'], {'userId': '42'});
    });

    test('rejects a runtime url that is not absolute', () {
      expect(
        () => AgUiTransport(runtimeUrl: Uri.parse('/api/copilotkit')),
        throwsArgumentError,
      );
      expect(
        () => AgUiTransport(runtimeUrl: Uri.parse('runtime.test')),
        throwsArgumentError,
      );
    });

    test('emits the error and closes when ag_ui rejects the url', () async {
      final badTransport = AgUiTransport(
        runtimeUrl: Uri.parse('ftp://runtime.test/api'),
        httpClientFactory: () => httpClient,
      );
      final errors = <Object>[];
      final done = Completer<void>();
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        badTransport
            .run(agentId: 'default', input: _input)
            .listen(null, onError: errors.add, onDone: done.complete);
        await done.future;
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
      expect(errors, hasLength(1));
      verify(() => httpClient.close()).called(1);
    });

    test('encodes the agent id in the route', () async {
      stubResponse(_sse(const Stream.empty()));

      await transport.run(agentId: 'my agent', input: _input).toList();

      final request =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.Request;
      expect(request.url.path, '/api/copilotkit/agent/my%20agent/run');
    });

    test('ignores a trailing slash in the runtime url', () async {
      transport = AgUiTransport(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit/'),
        httpClientFactory: () => httpClient,
      );
      stubResponse(_sse(const Stream.empty()));

      await transport.run(agentId: 'default', input: _input).toList();

      final request =
          verify(() => httpClient.send(captureAny())).captured.single
              as http.Request;
      expect(request.url.path, '/api/copilotkit/agent/default/run');
    });

    test('skips events it cannot decode and keeps streaming', () async {
      stubResponse(
        _sse(
          Stream.fromIterable([
            _event({'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'}),
            _event({'type': 'SOMETHING_NEW', 'payload': 1}),
            _event({'type': 'TEXT_MESSAGE_START'}),
            utf8.encode('data: {not json\n\n'),
            _event({'type': 'RUN_FINISHED', 'threadId': 't', 'runId': 'r'}),
          ]),
        ),
      );

      final events = await transport
          .run(agentId: 'default', input: _input)
          .toList();

      expect(events, [isA<RunStartedEvent>(), isA<RunFinishedEvent>()]);
    });

    test('emits an error when the runtime rejects the request', () async {
      stubResponse(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"Agent not found"}')),
          404,
        ),
      );

      await expectLater(
        transport.run(agentId: 'missing', input: _input),
        emitsError(isA<TransportError>()),
      );
    });

    test('closes the http client when the run ends', () async {
      stubResponse(_sse(const Stream.empty()));

      await transport.run(agentId: 'default', input: _input).toList();

      verify(() => httpClient.close()).called(1);
    });

    test('closes the http client when the subscription is cancelled', () async {
      final body = StreamController<List<int>>();
      // Like a real client, closing it ends the response body.
      when(() => httpClient.close()).thenAnswer((_) => body.close());
      stubResponse(_sse(body.stream));
      final started = Completer<void>();
      body.add(_event({'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'}));

      final subscription = transport
          .run(agentId: 'default', input: _input)
          .listen((_) => started.complete());
      await started.future;
      await subscription.cancel();

      verify(() => httpClient.close()).called(1);
    });

    test('forwards pause and resume to the response', () async {
      final body = StreamController<List<int>>();
      when(() => httpClient.close()).thenAnswer((_) => body.close());
      stubResponse(_sse(body.stream));
      final events = <BaseEvent>[];
      final subscription = transport
          .run(agentId: 'default', input: _input)
          .listen(events.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      subscription.pause();
      body.add(_event({'type': 'RUN_STARTED', 'threadId': 't', 'runId': 'r'}));
      await pumpEventQueue();
      expect(events, isEmpty);

      subscription.resume();
      await pumpEventQueue();
      expect(events, [isA<RunStartedEvent>()]);
    });

    test('close closes the http clients of active runs', () async {
      final body = StreamController<List<int>>();
      when(() => httpClient.close()).thenAnswer((_) => body.close());
      stubResponse(_sse(body.stream));
      final subscription = transport
          .run(agentId: 'default', input: _input)
          .listen((_) {});
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await transport.close();

      verify(() => httpClient.close()).called(1);
    });

    group('stop', () {
      test('posts the run id to the stop route with headers', () async {
        stubResponse(
          http.StreamedResponse(
            Stream.value(utf8.encode('{"stopped":true}')),
            200,
          ),
        );

        await transport.stop(
          agentId: 'my agent',
          threadId: 'thread 1',
          runId: 'run-1',
          headers: {'Authorization': 'Bearer token'},
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/copilotkit/agent/my%20agent/stop/thread%201',
        );
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(request.body), {'runId': 'run-1'});
        verify(() => httpClient.close()).called(1);
      });

      test('throws when the runtime rejects the stop', () async {
        stubResponse(
          http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"Agent not found"}')),
            404,
          ),
        );

        await expectLater(
          transport.stop(agentId: 'missing', threadId: 't', runId: 'r'),
          throwsA(
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              contains('404'),
            ),
          ),
        );
        verify(() => httpClient.close()).called(1);
      });
    });
  });
}
