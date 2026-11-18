import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';

import '../../../helpers/threads_fixture.dart';

const _json = <String, Object?>{
  'id': 't1',
  'agentId': 'default',
  'archived': false,
  'createdAt': '2026-11-18T12:50:35.978Z',
  'updatedAt': '2026-11-18T12:54:34.826Z',
  'name': 'Lighthouse',
};

/// Decodes the test thread with [changes] applied.
ThreadRecord decode([Map<String, Object?> changes = const {}]) =>
    ThreadRecord.fromJson({..._json, ...changes});

void main() {
  group(ThreadRecord, () {
    test('decodes a thread of a recorded runtime', () {
      final recorded =
          (threadsBody('list')! as Map<String, Object?>)['threads']! as List;

      final thread = ThreadRecord.fromJson(
        recorded.first! as Map<String, Object?>,
      );

      expect(thread.agentId, 'default');
      expect(thread.archived, isFalse);
      expect(thread.name, isNotEmpty);
      expect(thread.updatedAt.isAfter(thread.createdAt), isTrue);
    });

    test('decodes the fields it keeps', () {
      final thread = decode();

      expect(thread.id, 't1');
      expect(thread.name, 'Lighthouse');
      expect(thread.createdAt, DateTime.utc(2026, 11, 18, 12, 50, 35, 978));
      expect(thread.updatedAt, DateTime.utc(2026, 11, 18, 12, 54, 34, 826));
    });

    test('has no name while the runtime sends none', () {
      expect(decode({'name': null}).name, isNull);
      expect(ThreadRecord.fromJson(Map.of(_json)..remove('name')).name, isNull);
    });

    test('ignores fields it does not know', () {
      expect(decode({'somethingNew': true}).id, 't1');
    });

    test('throws when a field is missing or has the wrong type', () {
      expect(
        () => ThreadRecord.fromJson(Map.of(_json)..remove('id')),
        throwsA(isA<CheckedFromJsonException>()),
      );
      expect(
        () => decode({'archived': 'no'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('supports value equality', () {
      expect(decode(), decode({}));
      expect(decode(), isNot(decode({'archived': true})));
    });
  });
}
