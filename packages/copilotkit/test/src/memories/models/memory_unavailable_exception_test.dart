import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryUnavailableException, () {
    test('names its status', () {
      expect(
        const MemoryUnavailableException(404).toString(),
        'MemoryUnavailableException(404)',
      );
    });

    test('equals an exception with the same status', () {
      expect(
        const MemoryUnavailableException(404),
        const MemoryUnavailableException(404),
      );
      expect(
        const MemoryUnavailableException(404),
        isNot(const MemoryUnavailableException(403)),
      );
    });
  });
}
