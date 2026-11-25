import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/trajectory/trajectory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../helpers/trajectory_fixture.dart';

void main() {
  group(TrajectoryClient, () {
    late List<http.Request> sent;
    late Future<http.Response> Function(http.Request) answer;

    TrajectoryClient build({Duration timeout = const Duration(seconds: 10)}) =>
        TrajectoryClient(
          runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit/'),
          headers: () async => {'Authorization': 'Bearer token'},
          httpClientFactory: () => MockClient((request) {
            sent.add(request);
            return answer(request);
          }),
          timeout: timeout,
        );

    void replyWith(String step) {
      final row = trajectoryRow(step);
      answer = (_) async =>
          http.Response(jsonEncode(row['body']), row['status']! as int);
    }

    Matcher failsWith(String code, {int? status, bool retryable = false}) =>
        throwsA(
          isA<TrajectoryException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.statusCode, 'statusCode', status)
              .having((e) => e.isRetryable, 'isRetryable', retryable),
        );

    setUp(() => sent = []);

    test('asks the runtime for the grant of the trajectory', () async {
      replyWith('connect');

      final grant = await build().connect('id 1');

      final request = sent.single;
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse(
          'http://runtime.test/api/copilotkit/trajectory/id%201/connect',
        ),
      );
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.body, '{}');
      expect(grant.topic, startsWith('trajectory:'));
    });

    test('fails with the code of the recorded refusal', () {
      replyWith('connect-invalid-id');

      expect(
        build().connect('not-a-uuid'),
        failsWith('INVALID_REQUEST', status: 400),
      );
    });

    test('retries only a 5xx, 408 or 429', () async {
      for (final (status, retryable) in [
        (503, true),
        (408, true),
        (429, true),
        (403, false),
      ]) {
        answer = (_) async =>
            http.Response('{"code": "TRAJECTORIES_NOT_ENABLED"}', status);

        await expectLater(
          build().connect('id'),
          failsWith(
            'TRAJECTORIES_NOT_ENABLED',
            status: status,
            retryable: retryable,
          ),
        );
      }
    });

    test('fails with CONNECTION_FAILED without a usable code', () async {
      for (final body in ['not json', '{"code": "lower_case"}', '[]']) {
        answer = (_) async => http.Response(body, 502);

        await expectLater(
          build().connect('id'),
          failsWith('CONNECTION_FAILED', status: 502, retryable: true),
        );
      }
    });

    test('keeps the message of the refusal', () async {
      answer = (_) async =>
          http.Response('{"code": "X", "message": "No."}', 400);

      await expectLater(
        build().connect('id'),
        throwsA(
          isA<TrajectoryException>().having((e) => e.message, 'message', 'No.'),
        ),
      );
    });

    test('fails with INVALID_GRANT for an answer that is not a grant', () {
      answer = (_) async => http.Response('{"joinToken": ""}', 200);

      expect(build().connect('id'), failsWith('INVALID_GRANT', status: 200));
    });

    test('fails with a retryable error without an answer', () async {
      answer = (_) async => throw http.ClientException('offline');
      await expectLater(
        build().connect('id'),
        failsWith('CONNECTION_FAILED', retryable: true),
      );

      answer = (_) => Completer<http.Response>().future;
      await expectLater(
        build(timeout: const Duration(milliseconds: 10)).connect('id'),
        failsWith('CONNECTION_TIMEOUT', retryable: true),
      );
    });

    test('uses its own http client by default', () {
      expect(
        TrajectoryClient(runtimeUrl: Uri.parse('http://127.0.0.1:1'))
            .connect('id'),
        failsWith('CONNECTION_FAILED', retryable: true),
      );
    });
  });
}
