import 'package:json_utils/json_utils.dart';
import 'package:test/test.dart';

void main() {
  group(JsonPatcher, () {
    const patcher = JsonPatcher();

    Map<String, Object?> apply(
      Map<String, Object?> document,
      List<Map<String, Object?>> operations,
    ) => patcher.apply(document, operations);

    test('add sets object members and inserts into arrays', () {
      final result = apply(
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
        apply(
          {'a': 1},
          [
            {
              'op': 'add',
              'path': '',
              'value': {'b': 2},
            },
            {'op': 'add', 'path': '/c', 'value': 3},
          ],
        ),
        {'b': 2, 'c': 3},
      );
    });

    test('remove deletes object members and array elements', () {
      expect(
        apply(
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
        apply(
          {
            'a': 1,
            'b': [1, 2],
          },
          [
            {'op': 'replace', 'path': '/a', 'value': 9},
            {'op': 'replace', 'path': '/b/0', 'value': 8},
            {
              'op': 'replace',
              'path': '',
              'value': {'all': true},
            },
          ],
        ),
        {'all': true},
      );
      expect(
        apply(
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
        apply(
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
      final result = apply(
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
        apply(
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
        apply(
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

      apply(document, [
        {'op': 'add', 'path': '/a/b/-', 'value': 2},
        {'op': 'add', 'path': '/c', 'value': 3},
      ]);

      expect(document, {
        'a': {
          'b': [1],
        },
      });
    });

    test('a test passes without a value when the target is null', () {
      expect(
        apply(
          {'a': null},
          [
            {'op': 'test', 'path': '/a'},
          ],
        ),
        {'a': null},
      );
    });

    test('never mutates the operations', () {
      final value = <String, Object?>{'x': 1};

      final result = apply({}, [
        {'op': 'add', 'path': '/a', 'value': value},
        {'op': 'replace', 'path': '/a/x', 'value': 2},
      ]);

      expect(result, {
        'a': {'x': 2},
      });
      expect(value, {'x': 1});
    });

    group('throws a FormatException', () {
      final cases = <String, (Map<String, Object?>, Map<String, Object?>)>{
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
        'missing op': ({'a': 1}, {'path': '/a'}),
        'op that is not a string': ({'a': 1}, {'op': 1, 'path': '/a'}),
        'missing from': ({'a': 1}, {'op': 'move', 'path': '/b'}),
        'missing copy from': ({'a': 1}, {'op': 'copy', 'path': '/b'}),
        'pointer that is not a string': ({'a': 1}, {'op': 'remove', 'path': 1}),
        'root added as a non-object': (
          {'a': 1},
          {'op': 'add', 'path': '', 'value': 'new'},
        ),
        'root replaced with a non-object': (
          {'a': 1},
          {'op': 'replace', 'path': '', 'value': null},
        ),
      };
      for (final MapEntry(key: name, value: (document, operation))
          in cases.entries) {
        test(name, () {
          expect(() => apply(document, [operation]), throwsFormatException);
        });
      }
    });
  });
}
