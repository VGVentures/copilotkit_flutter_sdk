import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Built at run time: equal constants are one instance, which would skip
  // the comparison of props.
  final draft = NewMemory(content: ['x'].join(), kind: MemoryKind.topical);
  final id = ['a'].join();

  group(MemoriesEvent, () {
    test('MemoriesRequested compares by includeInvalidated', () {
      expect(
        MemoriesRequested(includeInvalidated: [true].first),
        MemoriesRequested(includeInvalidated: [true].first),
      );
      expect(
        MemoriesRequested(includeInvalidated: [true].first),
        isNot(MemoriesRequested(includeInvalidated: [false].first)),
      );
    });

    test('MemoriesRecalled compares by query, limit and scope', () {
      expect(
        MemoriesRecalled(id, limit: 1, scope: MemoryScope.user),
        MemoriesRecalled(id, limit: 1, scope: MemoryScope.user),
      );
      expect(MemoriesRecalled(id), isNot(MemoriesRecalled(id, limit: 1)));
    });

    test('MemorySaved compares by memory', () {
      expect(MemorySaved(draft), MemorySaved(draft));
    });

    test('MemorySuperseded compares by id and memory', () {
      expect(MemorySuperseded(id, draft), MemorySuperseded(id, draft));
      expect(MemorySuperseded(id, draft), isNot(MemorySuperseded('b', draft)));
    });

    test('MemoryRetired compares by id', () {
      expect(MemoryRetired(id), MemoryRetired(id));
      expect(MemoryRetired(id), isNot(MemoryRetired(['b'].join())));
    });
  });
}
