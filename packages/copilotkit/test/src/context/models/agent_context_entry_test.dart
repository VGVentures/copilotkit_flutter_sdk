import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import 'package:uuid/uuid.dart';

void main() {
  group(AgentContextEntry, () {
    test('generates an id when none is given', () {
      final entry = AgentContextEntry(
        description: 'Unread',
        value: const {'count': 3},
      );

      expect(Uuid.isValidUUID(fromString: entry.id), isTrue);
      expect(entry.description, 'Unread');
      expect(entry.value, const {'count': 3});
    });

    test('copyWith replaces the value and keeps the id', () {
      final entry = AgentContextEntry(
        description: 'Unread',
        value: const {'count': 3},
      );

      final copy = entry.copyWith(value: const {'count': 4});

      expect(copy.id, entry.id);
      expect(copy.description, 'Unread');
      expect(copy.value, const {'count': 4});
    });

    test('supports value equality', () {
      expect(
        AgentContextEntry(
          id: 'e1',
          description: 'Unread',
          value: const {'count': 3},
        ),
        AgentContextEntry(
          id: 'e1',
          description: 'Unread',
          value: const {'count': 3},
        ),
      );
      expect(
        AgentContextEntry(
          id: 'e1',
          description: 'Unread',
          value: const {'count': 3},
        ),
        isNot(
          AgentContextEntry(
            id: 'e2',
            description: 'Unread',
            value: const {'count': 3},
          ),
        ),
      );
    });
  });
}
