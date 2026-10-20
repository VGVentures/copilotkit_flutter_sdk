import 'package:ack/ack.dart';
import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/agent/agent.dart';
import 'package:copilotkit/src/client/run_input_builder.dart';
import 'package:copilotkit/src/context/context.dart';
import 'package:copilotkit/src/messages/messages.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class _MockUuid extends Mock implements Uuid;

void main() {
  group(RunInputBuilder, () {
    const user = UserMessage(id: 'u1', content: 'Hi');
    const agent = CopilotAgentState(
      agentId: 'default',
      threadId: 'thread-1',
      messages: [user],
      sharedState: SharedState({'count': 1}),
    );
    final tool = FrontendTool(
      name: 'showWeather',
      description: 'Show the weather',
      parameters: Ack.object({'city': Ack.string()}),
      decode: Map<String, Object?>.of,
      handler: (_, {required signal}) async => 'ok',
    );
    final entry = AgentContextEntry(
      id: 'user',
      description: 'Current user',
      value: const {'name': 'Ada'},
    );

    test('sends the messages as AG-UI messages, unchanged', () {
      final reasoning = const ag_ui.ReasoningMessage(
        id: 'r1',
        content: 'Thinking',
        encryptedValue: 'secret',
      ).toJson();
      final input = const RunInputBuilder().build(
        agent: agent.copyWith(
          messages: [
            user,
            const AssistantMessage(
              id: 'a1',
              toolCalls: [
                ToolCall(id: 'c1', name: 'showWeather', arguments: '{}'),
              ],
            ),
            UnsupportedMessage(id: 'r1', data: reasoning),
          ],
        ),
        tools: const [],
        context: const [],
      );

      expect(input.messages.map((message) => message.toJson()), [
        {'id': 'u1', 'role': 'user', 'content': 'Hi'},
        {
          'id': 'a1',
          'role': 'assistant',
          'toolCalls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'showWeather', 'arguments': '{}'},
            },
          ],
        },
        reasoning,
      ]);
    });

    test('builds the input from the agent, tools, context and properties', () {
      final uuid = _MockUuid();
      when(uuid.v4).thenReturn('run-1');

      final input = RunInputBuilder(uuid: uuid).build(
        agent: agent,
        tools: [tool],
        context: [entry],
        properties: const {'locale': 'en'},
      );

      expect(input.threadId, 'thread-1');
      expect(input.runId, 'run-1');
      expect(input.state, {'count': 1});
      expect(input.messages.map(Message.fromAgUi), [user]);
      expect(input.tools.single.name, 'showWeather');
      expect(input.tools.single.description, 'Show the weather');
      expect(input.tools.single.parameters, {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
        'additionalProperties': false,
      });
      expect(input.context.single.description, 'Current user');
      expect(input.context.single.value, '{"name":"Ada"}');
      expect(input.forwardedProps, {'locale': 'en'});
    });

    test('adds properties to empty object parameters', () {
      final input = const RunInputBuilder().build(
        agent: agent,
        tools: [
          FrontendTool(
            name: 'refresh',
            description: 'Refresh the screen',
            parameters: Ack.object({'options': Ack.object({})}),
            decode: Map<String, Object?>.of,
            handler: (_, {required signal}) async => 'ok',
          ),
        ],
        context: const [],
      );

      const empty = {
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, Object?>{},
      };
      expect(input.tools.single.parameters, {
        'type': 'object',
        'properties': {'options': empty},
        'required': ['options'],
        'additionalProperties': false,
      });
    });

    test('keeps the context order and JSON-encodes each value', () {
      final input = const RunInputBuilder().build(
        agent: agent,
        tools: const [],
        context: [
          entry,
          AgentContextEntry(
            description: 'Locale',
            value: const {'label': 'es'},
          ),
          AgentContextEntry(description: 'Unread', value: const {'count': 3}),
        ],
      );

      expect(input.context.map((c) => c.description), [
        'Current user',
        'Locale',
        'Unread',
      ]);
      expect(input.context.map((c) => c.value), [
        '{"name":"Ada"}',
        '{"label":"es"}',
        '{"count":3}',
      ]);
    });

    test('generates a new run id for every run by default', () {
      const builder = RunInputBuilder();
      ag_ui.RunAgentInput build() =>
          builder.build(agent: agent, tools: const [], context: const []);

      expect(build().runId, isNot(build().runId));
    });
  });
}
