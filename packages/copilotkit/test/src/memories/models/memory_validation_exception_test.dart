import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryValidationException, () {
    test('names its message', () {
      expect(
        const MemoryValidationException('too long').toString(),
        'MemoryValidationException: too long',
      );
    });

    test('equals an exception with the same message', () {
      expect(
        const MemoryValidationException('a'),
        const MemoryValidationException('a'),
      );
      expect(
        const MemoryValidationException('a'),
        isNot(const MemoryValidationException('b')),
      );
    });
  });
}
