import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallStatus, () {
    test('isFinished is true only once the call has ended', () {
      expect(
        {for (final status in ToolCallStatus.values) status: status.isFinished},
        {
          ToolCallStatus.inProgress: false,
          ToolCallStatus.executing: false,
          ToolCallStatus.complete: true,
          ToolCallStatus.failed: true,
          ToolCallStatus.cancelled: true,
        },
      );
    });
  });
}
