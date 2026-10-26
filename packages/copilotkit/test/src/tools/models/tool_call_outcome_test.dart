import 'package:copilotkit/src/tools/models/tool_call_outcome.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallOutcome, () {
    test('has no error or stack trace by default', () {
      const outcome = ToolCallOutcome(result: 'ok');

      expect(outcome.error, isNull);
      expect(outcome.stackTrace, isNull);
    });

    test('supports value equality', () {
      final stackTrace = StackTrace.current;

      expect(
        ToolCallOutcome(result: 'ok', error: 'boom', stackTrace: stackTrace),
        ToolCallOutcome(
          result: String.fromCharCodes('ok'.codeUnits),
          error: 'boom',
          stackTrace: stackTrace,
        ),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(const ToolCallOutcome(result: 'failed')),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(const ToolCallOutcome(result: 'ok', error: 'boom')),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(ToolCallOutcome(result: 'ok', stackTrace: stackTrace)),
      );
    });
  });
}
