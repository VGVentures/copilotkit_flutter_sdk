import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryScope, () {
    test('is found by its wire name', () {
      for (final scope in MemoryScope.values) {
        expect(MemoryScope.fromWireName(scope.wireName), scope);
      }
    });

    test('is null for a name it does not know', () {
      expect(MemoryScope.fromWireName('team'), isNull);
    });
  });
}
