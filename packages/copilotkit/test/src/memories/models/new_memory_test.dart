import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(NewMemory, () {
    test('encodes only the fields the runtime knows', () {
      expect(
        const NewMemory(
          content: 'Likes tea.',
          kind: MemoryKind.topical,
          scope: MemoryScope.project,
          sourceThreadIds: ['t1'],
        ).toJson(),
        {
          'content': 'Likes tea.',
          'kind': 'topical',
          'scope': 'project',
          'sourceThreadIds': ['t1'],
        },
      );
    });

    test('leaves the scope out so the runtime picks its default', () {
      expect(
        const NewMemory(content: 'x', kind: MemoryKind.episodic).toJson(),
        {'content': 'x', 'kind': 'episodic', 'sourceThreadIds': <String>[]},
      );
    });

    group('validate', () {
      test('accepts the largest content and the most thread ids', () {
        expect(
          NewMemory(
            content: 'x' * NewMemory.maxContentLength,
            kind: MemoryKind.topical,
            sourceThreadIds: List.filled(NewMemory.maxSourceThreadIds, 't'),
          ).validate,
          returnsNormally,
        );
      });

      test('rejects content that is too long', () {
        expect(
          NewMemory(
            content: 'x' * (NewMemory.maxContentLength + 1),
            kind: MemoryKind.topical,
          ).validate,
          throwsA(isA<MemoryValidationException>()),
        );
      });

      test('rejects too many source thread ids', () {
        expect(
          NewMemory(
            content: 'x',
            kind: MemoryKind.topical,
            sourceThreadIds: List.filled(NewMemory.maxSourceThreadIds + 1, 't'),
          ).validate,
          throwsA(isA<MemoryValidationException>()),
        );
      });
    });

    test('equals a memory with the same fields', () {
      NewMemory build() =>
          NewMemory(content: ['x'].join(), kind: MemoryKind.topical);

      expect(build(), build());
    });
  });
}
