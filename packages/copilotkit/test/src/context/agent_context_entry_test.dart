import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group(AgentContextEntry, () {
    test('generates an id when none is given', () {
      final entry = AgentContextEntry(description: 'Unread', value: 3);

      expect(Uuid.isValidUUID(fromString: entry.id), isTrue);
      expect(entry.description, 'Unread');
      expect(entry.value, 3);
    });

    test('sends to every agent unless agent ids are given', () {
      expect(AgentContextEntry(description: 'Unread').agentIds, isNull);
      expect(
        AgentContextEntry(
          description: 'Unread',
          agentIds: const {'ops'},
        ).agentIds,
        {'ops'},
      );
    });

    test('copyWith replaces the value and keeps the id and agent ids', () {
      final entry = AgentContextEntry(
        description: 'Unread',
        value: 3,
        agentIds: const {'ops'},
      );

      final copy = entry.copyWith(value: 4);

      expect(copy.id, entry.id);
      expect(copy.description, 'Unread');
      expect(copy.value, 4);
      expect(copy.agentIds, {'ops'});
    });

    test('supports value equality', () {
      expect(
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
      );
      expect(
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
        isNot(AgentContextEntry(id: 'e2', description: 'Unread', value: 3)),
      );
      expect(
        AgentContextEntry(
          id: 'e1',
          description: 'a',
          agentIds: const {'x', 'y'},
        ),
        AgentContextEntry(
          id: 'e1',
          description: 'a',
          agentIds: const {'y', 'x'},
        ),
      );
      expect(
        AgentContextEntry(id: 'e1', description: 'a', agentIds: const {'x'}),
        isNot(AgentContextEntry(id: 'e1', description: 'a')),
      );
    });
  });
}
