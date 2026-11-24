import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryKind, () {
    test('is found by its wire name', () {
      for (final kind in MemoryKind.values) {
        expect(MemoryKind.fromWireName(kind.wireName), kind);
      }
    });

    test('is null for a name it does not know', () {
      expect(MemoryKind.fromWireName('other'), isNull);
      expect(MemoryKind.fromWireName(null), isNull);
    });
  });
}
