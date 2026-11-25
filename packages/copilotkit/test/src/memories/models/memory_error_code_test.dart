import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(MemoryErrorCode, () {
    test('spells the codes of the other CopilotKit SDKs', () {
      expect(MemoryErrorCode.values.map((code) => code.wireName), [
        'MEMORY_LIST_FAILED',
        'MEMORY_RECALL_FAILED',
        'MEMORY_CREDENTIALS_FAILED',
        'MEMORY_MUTATION_FAILED',
        'MEMORY_REQUEST_TIMEOUT',
        // This SDK's own: core has no code for a channel that gave up.
        'MEMORY_REALTIME_UNAVAILABLE',
      ]);
    });
  });
}
