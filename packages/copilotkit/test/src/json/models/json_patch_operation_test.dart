import 'package:copilotkit/src/json/json.dart';
import 'package:test/test.dart';

void main() {
  group(JsonPatchOperation, () {
    group('fromJson', () {
      test('parses every op', () {
        expect(
          JsonPatchOperation.fromJson(const {
            'op': 'add',
            'path': '/a',
            'value': 1,
          }),
          const JsonPatchAdd(path: '/a', value: 1),
        );
        expect(
          JsonPatchOperation.fromJson(const {'op': 'remove', 'path': '/a'}),
          const JsonPatchRemove(path: '/a'),
        );
        expect(
          JsonPatchOperation.fromJson(const {
            'op': 'replace',
            'path': '/a',
            'value': 2,
          }),
          const JsonPatchReplace(path: '/a', value: 2),
        );
        expect(
          JsonPatchOperation.fromJson(const {
            'op': 'move',
            'from': '/a',
            'path': '/b',
          }),
          const JsonPatchMove(from: '/a', path: '/b'),
        );
        expect(
          JsonPatchOperation.fromJson(const {
            'op': 'copy',
            'from': '/a',
            'path': '/b',
          }),
          const JsonPatchCopy(from: '/a', path: '/b'),
        );
        expect(
          JsonPatchOperation.fromJson(const {
            'op': 'test',
            'path': '/a',
            'value': [1],
          }),
          const JsonPatchTest(path: '/a', value: [1]),
        );
      });

      test('throws a FormatException for an unknown op', () {
        expect(
          () => JsonPatchOperation.fromJson(const {'op': 'merge', 'path': ''}),
          throwsFormatException,
        );
      });

      test('throws a FormatException for a missing pointer', () {
        expect(
          () => JsonPatchOperation.fromJson(const {'op': 'remove'}),
          throwsFormatException,
        );
        expect(
          () => JsonPatchOperation.fromJson(const {'op': 'copy', 'path': '/a'}),
          throwsFormatException,
        );
      });
    });

    test('toJson round-trips through fromJson for every op', () {
      const operations = [
        JsonPatchAdd(path: '/a', value: 1),
        JsonPatchRemove(path: '/a'),
        JsonPatchReplace(path: '/a', value: 2),
        JsonPatchMove(from: '/a', path: '/b'),
        JsonPatchCopy(from: '/a', path: '/b'),
        JsonPatchTest(path: '/a', value: [1]),
      ];

      for (final operation in operations) {
        expect(JsonPatchOperation.fromJson(operation.toJson()), operation);
      }
    });

    test('toJson produces RFC 6902 operation objects', () {
      expect(const JsonPatchAdd(path: '/a', value: 1).toJson(), {
        'op': 'add',
        'path': '/a',
        'value': 1,
      });
      expect(const JsonPatchRemove(path: '/a').toJson(), {
        'op': 'remove',
        'path': '/a',
      });
      expect(const JsonPatchReplace(path: '/a', value: null).toJson(), {
        'op': 'replace',
        'path': '/a',
        'value': null,
      });
      expect(const JsonPatchMove(from: '/a', path: '/b').toJson(), {
        'op': 'move',
        'from': '/a',
        'path': '/b',
      });
      expect(const JsonPatchCopy(from: '/a', path: '/b').toJson(), {
        'op': 'copy',
        'from': '/a',
        'path': '/b',
      });
      expect(const JsonPatchTest(path: '/a', value: 1).toJson(), {
        'op': 'test',
        'path': '/a',
        'value': 1,
      });
    });

    test('supports value equality', () {
      expect(
        const JsonPatchAdd(path: '/a', value: 1),
        isNot(const JsonPatchAdd(path: '/a', value: 2)),
      );
      expect(
        const JsonPatchRemove(path: '/a'),
        isNot(const JsonPatchRemove(path: '/b')),
      );
      expect(
        const JsonPatchReplace(path: '/a', value: 1),
        isNot(const JsonPatchReplace(path: '/b', value: 1)),
      );
      expect(
        const JsonPatchMove(from: '/a', path: '/b'),
        isNot(const JsonPatchMove(from: '/b', path: '/a')),
      );
      expect(
        const JsonPatchCopy(from: '/a', path: '/b'),
        isNot(const JsonPatchCopy(from: '/b', path: '/a')),
      );
      expect(
        const JsonPatchTest(path: '/a', value: 1),
        isNot(const JsonPatchTest(path: '/a', value: 2)),
      );
    });
  });
}
