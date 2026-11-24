import 'package:copilotkit/src/threads/models/threads_error_code.dart';
import 'package:copilotkit/src/threads/models/threads_exception.dart';
import 'package:test/test.dart';

ThreadsException _failure({int? statusCode}) => ThreadsException(
  code: ThreadsErrorCode.listFailed,
  message: 'boom',
  statusCode: statusCode,
);

void main() {
  group(ThreadsException, () {
    test('is retryable without an answer or on a server error', () {
      expect(_failure().isRetryable, isTrue);
      expect(_failure(statusCode: 500).isRetryable, isTrue);
      expect(_failure(statusCode: 503).isRetryable, isTrue);
    });

    test('is not retryable on a client error', () {
      expect(_failure(statusCode: 400).isRetryable, isFalse);
      expect(_failure(statusCode: 404).isRetryable, isFalse);
      expect(_failure(statusCode: 499).isRetryable, isFalse);
    });

    test('names its code and message', () {
      expect(_failure().toString(), 'ThreadsException(listFailed): boom');
    });

    test('supports value equality', () {
      expect(_failure(statusCode: 500), _failure(statusCode: 500));
      expect(_failure(statusCode: 500), isNot(_failure(statusCode: 400)));
    });
  });
}
