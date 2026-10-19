import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(CopilotKitEvent, () {
    final tool = FrontendTool(
      name: 'showWeather',
      description: 'Weather',
      parameters: Ack.object({}),
      handler: (_, {required signal}) async => '',
    );
    final entry = AgentContextEntry(id: 'e1', description: 'User', value: 1);
    final message = UserMessage(id: 'u1', content: 'Hi');

    test('supports value equality', () {
      // Non-const instances, so equality goes through props.
      // ignore_for_file: prefer_const_constructors
      expect(AgentOpened('a'), AgentOpened('a'));
      expect(AgentOpened('a'), isNot(AgentOpened('b')));
      expect(ToolRegistered(tool), ToolRegistered(tool));
      expect(ToolUnregistered(tool), ToolUnregistered(tool));
      expect(ToolCallResponded('c1', 'ok'), ToolCallResponded('c1', 'ok'));
      expect(
        ToolCallResponded('c1', 'ok'),
        isNot(ToolCallResponded('c1', 'no')),
      );
      expect(
        ToolCallResponded('c1', 'ok'),
        isNot(ToolCallResponded('c2', 'ok')),
      );
      expect(ContextAdded(entry), ContextAdded(entry));
      expect(ContextUpdated('e1', 2), ContextUpdated('e1', 2));
      expect(ContextUpdated('e1', 2), isNot(ContextUpdated('e1', 3)));
      expect(ContextRemoved('e1'), ContextRemoved('e1'));
      expect(AgentRunRequested('a'), AgentRunRequested('a'));
      expect(
        AgentRunRequested('a', message: message),
        AgentRunRequested('a', message: message),
      );
      expect(
        AgentRunRequested('a', message: message),
        isNot(AgentRunRequested('a')),
      );
      expect(AgentStopRequested('a'), AgentStopRequested('a'));
      expect(AgentRunRequested('a'), isNot(AgentStopRequested('a')));
    });
  });
}
