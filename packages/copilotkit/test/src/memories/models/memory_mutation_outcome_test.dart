import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryMutationOutcome, () {
    const memory = Memory(
      id: 'm',
      kind: MemoryKind.topical,
      scope: MemoryScope.user,
      content: 'c',
      sourceThreadIds: [],
    );

    test('is not absorbed by default', () {
      expect(const MemoryMutationOutcome(memory: memory).isAbsorbed, isFalse);
    });

    test('equals an outcome with the same fields', () {
      expect(
        const MemoryMutationOutcome(memory: memory),
        const MemoryMutationOutcome(memory: memory),
      );
      expect(
        const MemoryMutationOutcome(memory: memory),
        isNot(const MemoryMutationOutcome(memory: memory, isAbsorbed: true)),
      );
    });
  });
}
