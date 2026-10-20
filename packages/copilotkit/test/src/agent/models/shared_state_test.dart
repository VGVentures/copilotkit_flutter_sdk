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

    test('throws what the decoder throws', () {
      expect(
        () => const SharedState({}).decode(_Counter.fromJson),
        throwsA(isA<TypeError>()),
      );
    });

    test('encodes as the object the agent sent', () {
      expect(const SharedState({'count': 2}).toJson(), {'count': 2});
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
