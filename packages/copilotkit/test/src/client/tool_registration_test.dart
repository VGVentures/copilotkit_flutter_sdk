import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;

    setUp(() {
      harness = ToolLoopHarness();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
    });

    List<RunAgentInput> sentInputs() => harness.sentInputs();

    group('registerTool', () {
      test('sends registered tools with their JSON Schema', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''));
        runs.add(const Stream.empty());

        await agent.run();

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

        await agent.run();

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

      test('the returned function unregisters the tool', () async {
        client.registerTool(weatherTool((_, {required signal}) async => ''))();
        runs.add(const Stream.empty());

        await agent.run();

        expect(sentInputs().single.tools, isEmpty);
      });

      test(
        'a stale unregister keeps a newer tool with the same name',
        () async {
          final unregisterOld = client.registerTool(
            weatherTool((_, {required signal}) async => 'old'),
          );
          client.registerTool(
            weatherTool((_, {required signal}) async => 'new'),
          );
          unregisterOld();
          runs.add(const Stream.empty());

          await agent.run();

          expect(sentInputs().single.tools, hasLength(1));
        },
      );
    });
  });
}
