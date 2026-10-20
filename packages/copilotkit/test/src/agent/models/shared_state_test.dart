import 'package:copilotkit/src/agent/agent.dart';
import 'package:test/test.dart';

/// A model decoded from shared state, for these tests.
class const _Counter(final int count) {
  factory fromJson(Map<String, Object?> json) =>
      _Counter(json['count']! as int);
}

void main() {
  group(SharedState, () {
    test('decodes a JSON object', () {
      expect(
        const SharedState({'count': 2}).decode(_Counter.fromJson).count,
        2,
      );
    });

    test('rejects decoding a value that is not a JSON object', () {
      expect(
        () => const SharedState(['a']).decode(_Counter.fromJson),
        throwsFormatException,
      );
    });

    test('encodes as the value the agent sent', () {
      expect(const SharedState(['a']).toJson(), ['a']);
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
