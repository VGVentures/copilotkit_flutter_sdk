import 'package:copilotkit/src/transport/models/stop_request.dart';
import 'package:test/test.dart';

void main() {
  group(StopRequest, () {
    test('encodes the run id', () {
      expect(const StopRequest(runId: 'run-1').toJson(), {'runId': 'run-1'});
    });

    test('supports value equality', () {
      expect(
        const StopRequest(runId: 'run-1'),
        StopRequest(runId: String.fromCharCodes('run-1'.codeUnits)),
      );
      expect(
        const StopRequest(runId: 'run-1'),
        isNot(const StopRequest(runId: 'run-2')),
      );
    });
  });
}
