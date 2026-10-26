import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/client/client.dart';
import 'package:test/test.dart';

void main() {
  group(ActiveRun, () {
    test('holds what a stop needs', () async {
      final subscription = const Stream<ag_ui.BaseEvent>.empty().listen(null);
      final run = ActiveRun(
        runId: 'r1',
        headers: const {'Authorization': 'Bearer token'},
        subscription: subscription,
      );

      expect(run.runId, 'r1');
      expect(run.headers, {'Authorization': 'Bearer token'});
      expect(run.subscription, same(subscription));
      await subscription.cancel();
    });
  });
}
