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
  });
}
