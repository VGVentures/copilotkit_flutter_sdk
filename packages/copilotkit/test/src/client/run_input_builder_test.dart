import 'package:ack/ack.dart';
import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/run_input_builder.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/json/json.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class _MockUuid extends Mock implements Uuid;

void main() {
  group(RunInputBuilder, () {
    final user = UserMessage(id: 'u1', content: 'Hi');
    final agent = CopilotAgentState(
      agentId: 'default',
      threadId: 'thread-1',
      messages: [user],
      sharedState: const SharedState({'count': 1}),
    );
    final tool = FrontendTool(
      name: 'showWeather',
      description: 'Show the weather',
      parameters: Ack.object({'city': Ack.string()}),
      decode: JsonObject.new,
      handler: (_, {required signal}) async => 'ok',
    );
    final entry = AgentContextEntry(
      id: 'user',
      description: 'Current user',
      value: const JsonObject({'name': 'Ada'}),
    );

    test('builds the input from the agent, tools, context and properties', () {
      final uuid = _MockUuid();
      when(uuid.v4).thenReturn('run-1');

      final input = RunInputBuilder(uuid: uuid).build(
        agent: agent,
        tools: [tool],
        context: [entry],
        properties: const JsonObject({'locale': 'en'}),
      );

      expect(input.threadId, 'thread-1');
      expect(input.runId, 'run-1');
      expect(input.state, {'count': 1});
      expect(input.messages, [user]);
      expect(input.tools.single.name, 'showWeather');
      expect(input.tools.single.description, 'Show the weather');
      expect(
        input.tools.single.parameters,
        const JsonSchemaEncoder().encode(tool.parameters),
      );
      expect(input.context.single.description, 'Current user');
      expect(input.context.single.value, '{"name":"Ada"}');
      expect(input.forwardedProps, {'locale': 'en'});
    });

    test('generates a new run id for every run by default', () {
      const builder = RunInputBuilder();
      RunAgentInput build() =>
          builder.build(agent: agent, tools: const [], context: const []);

      expect(build().runId, isNot(build().runId));
    });
  });
}
