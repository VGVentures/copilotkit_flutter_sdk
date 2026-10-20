import 'dart:convert';

import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolResponses, () {
    late ToolResponses responses;
    late CancellationSignal signal;

    setUp(() {
      responses = ToolResponses();
      signal = CancellationSignal();
    });

    test('wait completes with the answer', () async {
      final answer = responses.wait('c1', signal);
      responses.respond('c1', 'approved');

      expect(await answer, 'approved');
      expect(responses.isAnswered('c1'), isTrue);
    });

    test('keeps an answer that arrives before the wait', () async {
      responses.respond('c1', 'early');

      expect(await responses.wait('c1', signal), 'early');
    });

    test('JSON-encodes an answer that is not a string', () async {
      responses.respond('c1', {'approved': true});

      expect(await responses.wait('c1', signal), '{"approved":true}');
    });

    test('throws on an answer that cannot be encoded', () {
      expect(
        () => responses.respond('c1', DateTime(2026)),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(responses.isAnswered('c1'), isFalse);
    });

    test('only the first answer counts', () async {
      responses
        ..respond('c1', 'first')
        ..respond('c1', 'second');

      expect(await responses.wait('c1', signal), 'first');
    });

    test('a cancelled signal ends the wait as cancelled', () async {
      final answer = responses.wait('c1', signal);
      signal.cancel();

      expect(await answer, FallbackToolResult.cancelled.message);
    });

    test('remove forgets the call', () {
      responses
        ..respond('c1', 'ok')
        ..remove('c1');

      expect(responses.isAnswered('c1'), isFalse);
    });

    test('clear forgets every call', () {
      responses
        ..respond('c1', 'ok')
        ..respond('c2', 'ok')
        ..clear();

      expect(responses.isAnswered('c1'), isFalse);
      expect(responses.isAnswered('c2'), isFalse);
    });
  });
}
