import 'package:copilotkit/src/transport/stop_request.dart';
import 'package:test/test.dart';

void main() {
  group(StopRequest, () {
    test('encodes the run id', () {
      expect(const StopRequest(runId: 'run-1').toJson(), {'runId': 'run-1'});
    });
  });
}
