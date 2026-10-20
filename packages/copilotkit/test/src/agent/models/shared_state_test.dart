import 'package:copilotkit/src/agent/agent.dart';
import 'package:test/test.dart';

import '../../../helpers/json_values.dart';

/// A model decoded from shared state, for these tests.
class const _Counter(final int count) {
  factory fromJson(Map<String, Object?> json) =>
      _Counter(json['count']! as int);
}

void main() {
  group(SharedState, () {
    test('decodes a JSON object', () {
      expect(
        const SharedState({'count': 2}).decode(_Counter.fromJson),
        isA<_Counter>().having((counter) => counter.count, 'count', 2),
      );
    });

    test('encodes as a read-only JSON object', () {
      final json = const SharedState({'count': 2}).toJson();

      expect(json, {'count': 2});
      expect(() => json['count'] = 3, throwsUnsupportedError);
    });

    group('of', () {
      test('takes the JSON object of an app model', () {
        expect(
          SharedState.of(const Fields({'count': 2})),
          const SharedState({'count': 2}),
        );
      });

      test('rejects a model whose JSON is not an object', () {
        expect(() => SharedState.of(const Count(2)), throwsFormatException);
      });
    });

    group('fromJson', () {
      test('wraps a JSON object', () {
        expect(
          SharedState.fromJson(const {'count': 2}),
          const SharedState({'count': 2}),
        );
      });

      test('rejects a value that is not a JSON object', () {
        expect(() => SharedState.fromJson(const ['a']), throwsFormatException);
      });
    });

    test('supports value equality', () {
      // A separate instance, so equality isn't identity.
      expect(
        const SharedState({'count': 2}),
        SharedState(Map.of({'count': 2})),
      );
      expect(
        const SharedState({'count': 2}),
        isNot(const SharedState({'count': 3})),
      );
    });
  });
}
