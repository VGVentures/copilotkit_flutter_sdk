import 'package:copilotkit/src/threads/models/thread_metadata_event.dart';
import 'package:copilotkit/src/threads/models/thread_metadata_operation.dart';
import 'package:test/test.dart';

import '../../../helpers/thread_metadata_fixture.dart';

void main() {
  group(ThreadMetadataEvent, () {
    test('decodes a recorded rename with the thread as it is after', () {
      final event = ThreadMetadataEvent.fromJson(
        threadMetadataPayload('renamed'),
      );

      expect(event.operation, ThreadMetadataOperation.renamed);
      expect(event.threadId, 'faa78209-4331-482e-92e2-1ca740a363ea');
      expect(event.occurredAt, DateTime.utc(2026, 11, 25, 18, 41, 14, 37, 849));
      expect(event.thread?.id, event.threadId);
      expect(event.thread?.name, 'Request for Ok');
    });

    test('decodes every recorded operation', () {
      for (final operation in [
        'created',
        'renamed',
        'archived',
        'unarchived',
        'deleted',
      ]) {
        final event = ThreadMetadataEvent.fromJson(
          threadMetadataPayload(operation),
        );

        expect(event.operation.name, operation);
      }
      expect(
        ThreadMetadataEvent.fromJson(threadMetadataPayload('archived'))
            .thread
            ?.archived,
        isTrue,
      );
    });

    test('has no thread for a deletion', () {
      final event = ThreadMetadataEvent.fromJson(
        threadMetadataPayload('deleted'),
      );

      expect(event.thread, isNull);
    });

    test('has no thread when the payload carries none', () {
      final event = ThreadMetadataEvent.fromJson(const {
        'operation': 'updated',
        'threadId': 't1',
        'occurredAt': '2026-11-25T18:41:14Z',
      });

      expect(event.operation, ThreadMetadataOperation.updated);
      expect(event.thread, isNull);
    });

    test('rejects an operation it does not know', () {
      expect(
        () => ThreadMetadataEvent.fromJson(const {
          'operation': 'merged',
          'threadId': 't1',
          'occurredAt': '2026-11-25T18:41:14Z',
        }),
        throwsFormatException,
      );
    });

    test('rejects a payload without a thread id', () {
      expect(
        () => ThreadMetadataEvent.fromJson(const {
          'operation': 'deleted',
          'occurredAt': '2026-11-25T18:41:14Z',
        }),
        throwsFormatException,
      );
    });

    test('compares by value', () {
      final payload = threadMetadataPayload('created');

      expect(
        ThreadMetadataEvent.fromJson(payload),
        ThreadMetadataEvent.fromJson(payload),
      );
    });
  });
}
