import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotKitState, () {
    final tool = FrontendTool(
      name: 'showWeather',
      description: 'Weather',
      parameters: Ack.object({}),
      handler: (_, {required signal}) async => '',
    );
    final entry = AgentContextEntry(id: 'e1', description: 'User', value: 1);

    test('defaults to no agents, tools, context or turns', () {
      const state = CopilotKitState();

      expect(state.agents, isEmpty);
      expect(state.tools, isEmpty);
      expect(state.context, isEmpty);
      expect(state.turns, isEmpty);
    });

    test('copyWith replaces the given fields', () {
      final state = const CopilotKitState().copyWith(
        tools: {tool.name: tool},
        context: [entry],
      );
      final turn = TurnState(controller: CancellationController());

      expect(state.tools, {'showWeather': tool});
      expect(state.context, [entry]);
      expect(state.copyWith(turns: {'a': turn}).turns, {'a': turn});
      expect(state.copyWith().agents, isEmpty);
      expect(state.copyWith(), state);
    });

    test('supports value equality', () {
      expect(
        CopilotKitState(tools: {tool.name: tool}, context: [entry]),
        CopilotKitState(tools: {tool.name: tool}, context: [entry]),
      );
      expect(
        CopilotKitState(tools: {tool.name: tool}),
        isNot(const CopilotKitState()),
      );
    });
  });
}
