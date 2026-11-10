import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryException, () {
    MemoryException withStatus(int? statusCode) => MemoryException(
      code: MemoryErrorCode.listFailed,
      message: 'm',
      statusCode: statusCode,
    );

    test('is retryable on a 5xx or no answer', () {
      expect(withStatus(500).isRetryable, isTrue);
      expect(withStatus(null).isRetryable, isTrue);
    });

    test('is not retryable on a 4xx', () {
      expect(withStatus(400).isRetryable, isFalse);
      expect(withStatus(499).isRetryable, isFalse);
    });

    test('is retryable below 400', () {
      expect(withStatus(302).isRetryable, isTrue);
    });

    test('names its code', () {
      expect(
        withStatus(500).toString(),
        'MemoryException(MEMORY_LIST_FAILED): m',
      );
    });

    test('equals an exception with the same fields', () {
      expect(withStatus(500), withStatus(500));
      expect(withStatus(500), isNot(withStatus(501)));
    });
  });
}
