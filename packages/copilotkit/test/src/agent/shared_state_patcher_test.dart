import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:test/test.dart';

void main() {
  group(SharedStatePatcher, () {
    const patcher = SharedStatePatcher();

    test('applies the operations to the state', () {
      expect(
        patcher.apply(const SharedState({'count': 1}), const [
          JsonPatchReplace(path: '/count', value: 2),
          JsonPatchAdd(path: '/units', value: 'metric'),
        ]),
        const SharedState({'count': 2, 'units': 'metric'}),
      );
    });

    test('patches a missing state as an empty object', () {
      expect(
        patcher.apply(null, const [JsonPatchAdd(path: '/count', value: 1)]),
        const SharedState({'count': 1}),
      );
    });

    test('throws when an operation does not apply', () {
      expect(
        () => patcher.apply(const SharedState({}), const [
          JsonPatchRemove(path: '/missing'),
        ]),
        throwsFormatException,
      );
    });

    test('throws when the result is not a JSON object', () {
      expect(
        () => patcher.apply(const SharedState({}), const [
          JsonPatchReplace(path: '', value: ['a']),
        ]),
        throwsFormatException,
      );
    });
  });
}
