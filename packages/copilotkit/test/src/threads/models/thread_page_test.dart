import 'package:copilotkit/src/threads/models/thread_page.dart';
import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:test/test.dart';

import '../../../helpers/thread_metadata_fixture.dart';
import '../../../helpers/threads_fixture.dart';

const _thread = <String, Object?>{
  'id': 't1',
  'agentId': 'default',
  'archived': false,
  'createdAt': '2026-11-18T12:50:35.978Z',
  'updatedAt': '2026-11-18T12:54:34.826Z',
};

void main() {
  group(ThreadPage, () {
    test('decodes a page of a recorded runtime', () {
      final page = ThreadPage.fromJson(
        threadsBody('list-page-1')! as Map<String, Object?>,
      );

      expect(page.threads, hasLength(1));
      expect(page.nextCursor, isNotEmpty);
      expect(page.hasNext, isTrue);
    });

    test('keeps the join code of the metadata channel', () {
      final page = ThreadPage.fromJson(
        threadMetadataBody('list')! as Map<String, Object?>,
      );

      expect(page.joinCode, '<join-code>');
      expect(
        ThreadPage.fromJson(const {'threads': <Object?>[]}).joinCode,
        isNull,
      );
    });

    test('has no next page without a cursor', () {
      final page = ThreadPage.fromJson(const {
        'threads': [_thread],
        'nextCursor': null,
      });

      expect(page.hasNext, isFalse);
      expect(
        ThreadPage.fromJson(const {'threads': <Object?>[]}).threads,
        isEmpty,
      );
    });

    test('keeps the threads read-only', () {
      final page = ThreadPage.fromJson(const {
        'threads': [_thread],
      });

      expect(
        () => page.threads.add(ThreadRecord.fromJson(_thread)),
        throwsUnsupportedError,
      );
    });

    test('throws when the body has no threads list', () {
      expect(
        () => ThreadPage.fromJson(const {'nextCursor': null}),
        throwsFormatException,
      );
    });

    test('supports value equality', () {
      final page = ThreadPage.fromJson(const {
        'threads': [_thread],
        'nextCursor': 'c',
      });

      expect(
        page,
        ThreadPage.fromJson({
          'threads': [Map.of(_thread)],
          'nextCursor': 'c',
        }),
      );
      expect(
        page,
        isNot(
          ThreadPage.fromJson(const {
            'threads': [_thread],
          }),
        ),
      );
    });
  });
}
