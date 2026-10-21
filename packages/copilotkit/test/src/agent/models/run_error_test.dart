import 'package:copilotkit/src/agent/agent.dart';
import 'package:test/test.dart';

void main() {
  group(RunError, () {
    test('has no code by default', () {
      expect(const RunError(message: 'Bad key').code, isNull);
    });

    test('is an exception', () {
      expect(const RunError(message: 'Bad key'), isA<Exception>());
    });

    test('supports value equality', () {
      expect(
        const RunError(message: 'Bad key', code: 'AUTH'),
        RunError(
          message: String.fromCharCodes('Bad key'.codeUnits),
          code: 'AUTH',
        ),
      );
      expect(
        const RunError(message: 'Bad key', code: 'AUTH'),
        isNot(const RunError(message: 'Bad key')),
      );
    });

    group('toString', () {
      test('names the message', () {
        expect(
          const RunError(message: 'Bad key').toString(),
          'RunError: Bad key',
        );
      });

      test('names the code when there is one', () {
        expect(
          const RunError(message: 'Bad key', code: 'AUTH').toString(),
          'RunError(AUTH): Bad key',
        );
      });
    });
  });
}
