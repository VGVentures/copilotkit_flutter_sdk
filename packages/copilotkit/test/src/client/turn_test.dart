import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/client.dart';
import 'package:test/test.dart';

void main() {
  group(Turn, () {
    test('starts with its agent, a live signal and no run', () {
      final agent = CopilotAgent(agentId: 'default');
      final turn = Turn(agent);

      expect(turn.agent, same(agent));
      expect(turn.signal.isCancelled, isFalse);
      expect(turn.run, isNull);
    });

    test('holds the attached run until it is detached', () async {
      final turn = Turn(CopilotAgent(agentId: 'default'));
      final subscription = const Stream<ag_ui.BaseEvent>.empty().listen(null);
      final run = ActiveRun(
        runId: 'r1',
        headers: const {},
        subscription: subscription,
      );

      turn.attach(run);
      expect(turn.run, same(run));

      turn.detach();
      expect(turn.run, isNull);
      await subscription.cancel();
    });
  });
}
