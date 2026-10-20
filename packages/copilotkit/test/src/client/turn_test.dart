import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/client.dart';
import 'package:test/test.dart';

void main() {
  group(Turn, () {
    test('starts with its agent, a live signal and no run', () {
      final agent = CopilotKitAgent(agentId: 'default');
      final turn = Turn(agent);

      expect(turn.agent, same(agent));
      expect(turn.signal.isCancelled, isFalse);
      expect(turn.run, isNull);
    });
  });

  group(ActiveRun, () {
    test('holds what a stop needs', () async {
      final subscription = const Stream<BaseEvent>.empty().listen(null);
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
