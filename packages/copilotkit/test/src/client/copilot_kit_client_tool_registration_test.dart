import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_harness.dart';
import '../../helpers/mock_agent_transport.dart';
import '../../helpers/tool_runs.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient frontend tools', () {
    late ClientHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;

    setUp(() async {
      harness = ClientHarness();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
    });

    List<RunAgentInput> sentInputs() => harness.transport.sentInputs();

    group('registerTool', () {
      test('sends registered tools with their JSON Schema', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''));
        runs.add(const Stream.empty());
        await client.runAgent(agent.state.agentId);

        final tool = sentInputs().single.tools.single;
        expect(tool.name, 'showWeather');
        expect(tool.description, 'Show the weather for a city');
        expect(tool.parameters, {
          'type': 'object',
          'properties': {
            'city': {'type': 'string', 'description': 'City name'},
            'days': {'type': 'integer'},
          },
          'required': ['city'],
          'additionalProperties': false,
        });
      });

      test('sends empty properties for empty object schemas', () async {
        client.registerTool(
          FrontendTool(
            name: 'refresh',
            description: 'Refresh the screen',
            parameters: Ack.object({'options': Ack.object({})}),
            handler: (_, {required signal}) async => '',
          ),
        );
        runs.add(const Stream.empty());
        await client.runAgent(agent.state.agentId);

        expect(sentInputs().single.tools.single.parameters, {
          'type': 'object',
          'properties': {
            'options': {
              'type': 'object',
              'additionalProperties': false,
              'properties': <String, Object?>{},
            },
          },
          'required': ['options'],
          'additionalProperties': false,
        });
      });

      final tool = weatherTool((_, {required signal}) async => '');

      test('unregisterTool removes the tool', () async {
        client.registerTool(tool);
        expect(client.tools, {'showWeather': tool});

        client.unregisterTool(tool);
        runs.add(const Stream.empty());
        await client.runAgent(agent.state.agentId);

        expect(client.tools, isEmpty);
        expect(sentInputs().single.tools, isEmpty);
      });

      final old = weatherTool((_, {required signal}) async => 'old');
      final newer = weatherTool((_, {required signal}) async => 'new');

      test('unregistering a replaced tool keeps the newer one', () async {
        client
          ..registerTool(old)
          ..registerTool(newer)
          ..unregisterTool(old);
        runs.add(const Stream.empty());
        await client.runAgent(agent.state.agentId);

        expect(client.tools, {'showWeather': newer});
        expect(sentInputs().single.tools, hasLength(1));
      });
    });
  });
}
