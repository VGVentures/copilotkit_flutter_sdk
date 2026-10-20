import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallOutcome, () {
    test('has no error and valid arguments by default', () {
      const outcome = ToolCallOutcome(result: 'ok');

      expect(outcome.error, isNull);
      expect(outcome.stackTrace, isNull);
      expect(outcome.invalidArguments, isFalse);
    });

    test('supports value equality', () {
      // A separate instance, so equality isn't identity.
      expect(
        const ToolCallOutcome(result: 'ok'),
        ToolCallOutcome(result: String.fromCharCodes('ok'.codeUnits)),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(const ToolCallOutcome(result: 'ok', error: 'boom')),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(const ToolCallOutcome(result: 'ok', invalidArguments: true)),
      );
    });
  });
}
