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
