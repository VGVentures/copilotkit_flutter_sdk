import 'package:copilotkit/src/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('applyJsonPatch', () {
    test('add sets object members and inserts into arrays', () {
      final result = applyJsonPatch(
        {
          'foo': ['bar', 'baz'],
        },
        [
          {'op': 'add', 'path': '/baz', 'value': 'qux'},
          {'op': 'add', 'path': '/foo/1', 'value': 'mid'},
          {'op': 'add', 'path': '/foo/-', 'value': 'end'},
        ],
      );

      expect(result, {
        'foo': ['bar', 'mid', 'baz', 'end'],
        'baz': 'qux',
      });
    });

    test('add at the root replaces the document', () {
      expect(
        applyJsonPatch(
          {'a': 1},
          [
            {'op': 'add', 'path': '', 'value': 'new'},
          ],
        ),
        'new',
      );
    });

    test('add on a null document creates it from the root', () {
      expect(
        applyJsonPatch(null, [
          {
            'op': 'add',
            'path': '',
            'value': {'a': 1},
          },
          {'op': 'add', 'path': '/b', 'value': 2},
        ]),
        {'a': 1, 'b': 2},
      );
    });

    test('remove deletes object members and array elements', () {
      expect(
        applyJsonPatch(
          {
            'a': 1,
            'b': [1, 2, 3],
          },
          [
            {'op': 'remove', 'path': '/a'},
            {'op': 'remove', 'path': '/b/1'},
          ],
        ),
        {
          'b': [1, 3],
        },
      );
    });

    test('replace swaps existing values', () {
      expect(
        applyJsonPatch(
          {
            'a': 1,
            'b': [1, 2],
          },
          [
            {'op': 'replace', 'path': '/a', 'value': 9},
            {'op': 'replace', 'path': '/b/0', 'value': 8},
            {'op': 'replace', 'path': '', 'value': 'all'},
          ],
        ),
        'all',
      );
      expect(
        applyJsonPatch(
          {
            'b': [1, 2],
          },
          [
            {'op': 'replace', 'path': '/b/0', 'value': 8},
          ],
        ),
        {
          'b': [8, 2],
        },
      );
    });

    test('move and copy relocate values', () {
      expect(
        applyJsonPatch(
          {
            'a': {'x': 1},
            'b': <String, Object?>{},
          },
          [
            {'op': 'move', 'from': '/a/x', 'path': '/b/y'},
            {'op': 'copy', 'from': '/b', 'path': '/c'},
          ],
        ),
        {
          'a': <String, Object?>{},
          'b': {'y': 1},
          'c': {'y': 1},
        },
      );
    });

    test('copy makes an independent value', () {
      final result = applyJsonPatch(
        {
          'a': {'x': 1},
        },
        [
          {'op': 'copy', 'from': '/a', 'path': '/b'},
          {'op': 'replace', 'path': '/b/x', 'value': 2},
        ],
      );

      expect(result, {
        'a': {'x': 1},
        'b': {'x': 2},
      });
    });

    test('test passes on deep-equal values', () {
      expect(
        applyJsonPatch(
          {
            'a': [
              {'b': 1},
              null,
              true,
            ],
          },
          [
            {
              'op': 'test',
              'path': '/a',
              'value': [
                {'b': 1},
                null,
                true,
              ],
            },
          ],
        ),
        {
          'a': [
            {'b': 1},
            null,
            true,
          ],
        },
      );
    });

    test('decodes ~0 and ~1 in pointers', () {
      expect(
        applyJsonPatch(
          {'a/b': 1, 'm~n': 2},
          [
            {'op': 'replace', 'path': '/a~1b', 'value': 3},
            {'op': 'replace', 'path': '/m~0n', 'value': 4},
          ],
        ),
        {'a/b': 3, 'm~n': 4},
      );
    });

    test('never mutates the input document', () {
      final document = {
        'a': {
          'b': [1],
        },
      };

      applyJsonPatch(document, [
        {'op': 'add', 'path': '/a/b/-', 'value': 2},
        {'op': 'add', 'path': '/c', 'value': 3},
      ]);

      expect(document, {
        'a': {
          'b': [1],
        },
      });
    });

    group('throws a FormatException', () {
      final cases = <String, (Object?, Map<String, Object?>)>{
        'unknown op': ({'a': 1}, {'op': 'merge', 'path': '/a'}),
        'missing path': ({'a': 1}, {'op': 'remove'}),
        'pointer without leading slash': (
          {'a': 1},
          {'op': 'remove', 'path': 'a'},
        ),
        'missing member': ({'a': 1}, {'op': 'remove', 'path': '/b'}),
        'missing parent': ({'a': 1}, {'op': 'add', 'path': '/x/y', 'value': 1}),
        'array index out of range': (
          {
            'a': [1],
          },
          {'op': 'add', 'path': '/a/5', 'value': 1},
        ),
        'array index not a number': (
          {
            'a': [1],
          },
          {'op': 'replace', 'path': '/a/x', 'value': 1},
        ),
        'remove dash': (
          {
            'a': [1],
          },
          {'op': 'remove', 'path': '/a/-'},
        ),
        'path through a scalar': (
          {'a': 1},
          {'op': 'add', 'path': '/a/b', 'value': 1},
        ),
        'failed test': ({'a': 1}, {'op': 'test', 'path': '/a', 'value': 2}),
        'failed test on map size': (
          {
            'a': {'x': 1},
          },
          {
            'op': 'test',
            'path': '/a',
            'value': {'x': 1, 'y': 2},
          },
        ),
        'failed test on list': (
          {
            'a': [1, 2],
          },
          {
            'op': 'test',
            'path': '/a',
            'value': [1, 3],
          },
        ),
        'failed test on list length': (
          {
            'a': [1],
          },
          {
            'op': 'test',
            'path': '/a',
            'value': [1, 2],
          },
        ),
        'failed test on missing key': (
          {
            'a': {'x': 1},
          },
          {
            'op': 'test',
            'path': '/a',
            'value': {'y': 1},
          },
        ),
        'remove root': ({'a': 1}, {'op': 'remove', 'path': ''}),
        'missing from': ({'a': 1}, {'op': 'move', 'path': '/b'}),
      };
      for (final MapEntry(key: name, value: (document, operation))
          in cases.entries) {
        test(name, () {
          expect(
            () => applyJsonPatch(document, [operation]),
            throwsFormatException,
          );
        });
      }
    });
  });
}
