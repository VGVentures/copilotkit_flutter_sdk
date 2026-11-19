import 'dart:convert';

import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/memory_fixtures.dart';

Map<String, Object?> _json({Map<String, Object?> overrides = const {}}) => {
  'id': 'm1',
  'kind': 'topical',
  'scope': 'user',
  'content': 'Likes tea.',
  'sourceThreadIds': ['t1'],
  'invalidatedAt': null,
  ...overrides,
};

void main() {
  group(Memory, () {
    group('fromJson', () {
      test('reads every field and ignores the ones it does not know', () {
        final json = jsonDecode(memoryFixture('list')) as Map<String, Object?>;
        final memories = (json['memories']! as List)
            .cast<Map<String, Object?>>();

        expect(
          Memory.fromJson(memories.first),
          const Memory(
            id: 'mem_2',
            kind: MemoryKind.operational,
            scope: MemoryScope.project,
            content: 'Always answer in metric units.',
            sourceThreadIds: [],
          ),
        );
        expect(
          Memory.fromJson(memories.last),
          Memory(
            id: 'mem_1',
            kind: MemoryKind.topical,
            scope: MemoryScope.user,
            content: 'Prefers window seats.',
            sourceThreadIds: const ['thread_a', 'thread_b'],
            invalidatedAt: DateTime.utc(2026, 5, 1, 10, 30),
          ),
        );
      });

      test('reads the score of a recalled memory as a double', () {
        expect(Memory.fromJson(_json(overrides: {'score': 1})).score, 1.0);
      });

      test('treats a missing invalidatedAt as live', () {
        final json = _json()..remove('invalidatedAt');

        expect(Memory.fromJson(json).isRetired, isFalse);
      });

      test('keeps the source thread ids unmodifiable', () {
        expect(
          () => Memory.fromJson(_json()).sourceThreadIds.add('t2'),
          throwsUnsupportedError,
        );
      });

      for (final (name, overrides) in <(String, Map<String, Object?>)>[
        ('an empty id', {'id': ''}),
        ('a missing id', {'id': null}),
        ('an unknown kind', {'kind': 'other'}),
        ('an unknown scope', {'scope': 'team'}),
        ('a content that is not a string', {'content': 1}),
        ('source thread ids that are not a list', {'sourceThreadIds': 'a'}),
        (
          'source thread ids that are not strings',
          {
            'sourceThreadIds': [1],
          },
        ),
        ('a score that is not a number', {'score': 'high'}),
        ('an invalidatedAt that is not a string', {'invalidatedAt': 1}),
      ]) {
        test('throws on $name', () {
          expect(
            () => Memory.fromJson(_json(overrides: overrides)),
            throwsFormatException,
          );
        });
      }
    });

    test('is retired once invalidatedAt is set', () {
      expect(
        Memory.fromJson(
          _json(overrides: {'invalidatedAt': '2026-01-01T00:00:00Z'}),
        ).isRetired,
        isTrue,
      );
    });

    test('equals a memory with the same fields', () {
      expect(Memory.fromJson(_json()), Memory.fromJson(_json()));
      expect(
        Memory.fromJson(_json()),
        isNot(Memory.fromJson(_json(overrides: {'id': 'm2'}))),
      );
    });
  });
}
