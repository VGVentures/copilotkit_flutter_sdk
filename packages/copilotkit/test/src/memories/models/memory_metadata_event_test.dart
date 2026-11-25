import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/memory_metadata_fixture.dart';

void main() {
  group(MemoryMetadataEvent, () {
    test('decodes a recorded creation with the memory', () {
      final event = MemoryMetadataEvent.fromJson(
        memoryMetadataPayload('created'),
      );

      expect(event.operation, MemoryMetadataOperation.created);
      expect(event.memoryId, 'e5e32c5d-780f-44d4-9a9f-5dd47dc43936');
      expect(event.occurredAt.isUtc, isTrue);
      expect(event.memory?.id, event.memoryId);
      expect(event.memory?.content, 'The user prefers metric units.');
      expect(event.memory?.kind, MemoryKind.topical);
      expect(event.memory?.scope, MemoryScope.user);
    });

    test('decodes a recorded invalidation without a memory', () {
      final event = MemoryMetadataEvent.fromJson(
        memoryMetadataPayload('invalidated'),
      );

      expect(event.operation, MemoryMetadataOperation.invalidated);
      expect(event.memory, isNull);
    });

    test('decodes an update', () {
      final payload = {
        ...memoryMetadataPayload('created'),
        'operation': 'updated',
      };

      expect(
        MemoryMetadataEvent.fromJson(payload).operation,
        MemoryMetadataOperation.updated,
      );
    });

    test('rejects what it cannot read', () {
      final created = memoryMetadataPayload('created');
      for (final payload in [
        {...created, 'operation': 'merged'},
        {...created, 'memoryId': ''},
        {...created, 'memory': null},
      ]) {
        expect(
          () => MemoryMetadataEvent.fromJson(payload),
          throwsFormatException,
          reason: '$payload',
        );
      }
    });

    test('compares by value', () {
      final payload = memoryMetadataPayload('created');

      expect(
        MemoryMetadataEvent.fromJson(payload),
        MemoryMetadataEvent.fromJson(payload),
      );
    });
  });
}
