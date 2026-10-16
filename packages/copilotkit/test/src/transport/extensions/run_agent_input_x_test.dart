import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/extensions/run_agent_input_x.dart';
import 'package:test/test.dart';

void main() {
  group('RunAgentInputX', () {
    test('toSimpleInput copies every field', () {
      final messages = [UserMessage(id: 'u1', content: 'Hi')];
      const tools = [
        Tool(
          name: 'showWeather',
          description: 'Weather',
          parameters: <String, Object?>{},
        ),
      ];
      const context = [Context(description: 'User', value: '"Ada"')];
      final input = RunAgentInput(
        threadId: 'thread-1',
        runId: 'run-1',
        parentRunId: 'run-0',
        state: const {'count': 1},
        messages: messages,
        tools: tools,
        context: context,
        forwardedProps: const {'userId': '42'},
      );

      final simple = input.toSimpleInput();

      expect(simple.threadId, 'thread-1');
      expect(simple.runId, 'run-1');
      expect(simple.parentRunId, 'run-0');
      expect(simple.state, {'count': 1});
      expect(simple.messages, same(messages));
      expect(simple.tools, same(tools));
      expect(simple.context, same(context));
      expect(simple.forwardedProps, {'userId': '42'});
    });
  });
}
