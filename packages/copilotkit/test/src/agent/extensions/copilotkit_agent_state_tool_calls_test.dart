import 'package:copilotkit/src/agent/extensions/copilotkit_agent_state_tool_calls.dart';
import 'package:copilotkit/src/agent/models/copilotkit_agent_state.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

const _first = ToolCallView(
  id: 'c1',
  name: 'showWeather',
  status: ToolCallStatus.executing,
);

const _second = ToolCallView(
  id: 'c2',
  name: 'showWeather',
  status: ToolCallStatus.executing,
);

const _state = CopilotKitAgentState(
  agentId: 'default',
  threadId: 'thread-1',
  toolCalls: [_first, _second],
);

void main() {
  group('CopilotKitAgentStateToolCalls', () {
    group('updateToolCall', () {
      test('replaces only the view of the call', () {
        final state = _state.updateToolCall('c2', (view) => view.complete('x'));

        expect(state.toolCalls, [_first, _second.complete('x')]);
      });

      test('returns the state unchanged for an unknown call', () {
        expect(
          _state.updateToolCall('x', (view) => view.complete('x')),
          _state,
        );
      });

      test('returns the state unchanged when the view does not change', () {
        expect(_state.updateToolCall('c1', (view) => view), _state);
      });
    });
  });
}
