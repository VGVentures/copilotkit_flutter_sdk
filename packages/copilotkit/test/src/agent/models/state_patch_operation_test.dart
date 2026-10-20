import 'package:copilotkit/src/agent/agent.dart';
import 'package:test/test.dart';

void main() {
  group(StatePatchOperation, () {
    group('toJson', () {
      test('add', () {
        expect(const StatePatchAdd(path: '/a', value: 1).toJson(), {
          'op': 'add',
          'path': '/a',
          'value': 1,
        });
      });

      test('remove', () {
        expect(const StatePatchRemove(path: '/a').toJson(), {
          'op': 'remove',
          'path': '/a',
        });
      });

      test('replace', () {
        expect(const StatePatchReplace(path: '/a', value: null).toJson(), {
          'op': 'replace',
          'path': '/a',
          'value': null,
        });
      });

      test('move', () {
        expect(const StatePatchMove(from: '/a', path: '/b').toJson(), {
          'op': 'move',
          'from': '/a',
          'path': '/b',
        });
      });

      test('copy', () {
        expect(const StatePatchCopy(from: '/a', path: '/b').toJson(), {
          'op': 'copy',
          'from': '/a',
          'path': '/b',
        });
      });

      test('test', () {
        expect(const StatePatchTest(path: '/a', value: [1]).toJson(), {
          'op': 'test',
          'path': '/a',
          'value': [1],
        });
      });
    });

    group('supports value equality', () {
      test('add', () {
        expect(
          const StatePatchAdd(path: '/a', value: [1]),
          StatePatchAdd(path: '/a', value: List.of([1])),
        );
        expect(
          const StatePatchAdd(path: '/a', value: 1),
          isNot(const StatePatchAdd(path: '/a', value: 2)),
        );
      });

      test('remove', () {
        expect(
          const StatePatchRemove(path: '/a'),
          StatePatchRemove(path: String.fromCharCodes('/a'.codeUnits)),
        );
        expect(
          const StatePatchRemove(path: '/a'),
          isNot(const StatePatchRemove(path: '/b')),
        );
      });

      test('replace', () {
        expect(
          const StatePatchReplace(path: '/a', value: {'x': 1}),
          StatePatchReplace(path: '/a', value: Map.of({'x': 1})),
        );
        expect(
          const StatePatchReplace(path: '/a', value: 1),
          isNot(const StatePatchReplace(path: '/b', value: 1)),
        );
      });

      test('move', () {
        expect(
          const StatePatchMove(from: '/a', path: '/b'),
          StatePatchMove(
            from: '/a',
            path: String.fromCharCodes('/b'.codeUnits),
          ),
        );
        expect(
          const StatePatchMove(from: '/a', path: '/b'),
          isNot(const StatePatchMove(from: '/b', path: '/a')),
        );
      });

      test('copy', () {
        expect(
          const StatePatchCopy(from: '/a', path: '/b'),
          StatePatchCopy(
            from: '/a',
            path: String.fromCharCodes('/b'.codeUnits),
          ),
        );
        expect(
          const StatePatchCopy(from: '/a', path: '/b'),
          isNot(const StatePatchCopy(from: '/b', path: '/a')),
        );
      });

      test('test', () {
        expect(
          const StatePatchTest(path: '/a', value: [1]),
          StatePatchTest(path: '/a', value: List.of([1])),
        );
        expect(
          const StatePatchTest(path: '/a', value: 1),
          isNot(const StatePatchTest(path: '/a', value: 2)),
        );
      });
    });
  });
}
