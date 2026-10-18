import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../helpers/client_x.dart';
import '../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(ToolLoopHarness.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late CopilotKitClient client;
    late CopilotAgent agent;
    late List<Stream<BaseEvent>> runs;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
    });

    List<RunAgentInput> sentInputs() => harness.sentInputs();

    group('registerTool', () {
      test('sends registered tools with their JSON Schema', () async {
        await client.registerTool(
          weatherTool((_, {required signal}) async => ''),
        );
        runs.add(const Stream.empty());

        await client.runAgent(agent);

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
        await client.registerTool(
          FrontendTool(
            name: 'refresh',
            description: 'Refresh the screen',
            parameters: Ack.object({'options': Ack.object({})}),
            handler: (_, {required signal}) async => '',
          ),
        );
        runs.add(const Stream.empty());

        await client.runAgent(agent);

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

      test('ToolUnregistered removes the tool', () async {
        final tool = weatherTool((_, {required signal}) async => '');
        await client.registerTool(tool);
        expect(client.state.tools, {'showWeather': tool});

        await client.unregisterTool(tool);
        runs.add(const Stream.empty());
        await client.runAgent(agent);

        expect(client.state.tools, isEmpty);
        expect(sentInputs().single.tools, isEmpty);
      });

      test(
        'a stale ToolUnregistered keeps a newer tool with the same name',
        () async {
          final old = weatherTool((_, {required signal}) async => 'old');
          final newer = weatherTool((_, {required signal}) async => 'new');
          await client.registerTool(old);
          await client.registerTool(newer);

          await client.unregisterTool(old);
          runs.add(const Stream.empty());
          await client.runAgent(agent);

          expect(client.state.tools, {'showWeather': newer});
          expect(sentInputs().single.tools, hasLength(1));
        },
      );

      test(
        'unregistering the active tool brings back the one it replaced',
        () async {
          final old = weatherTool((_, {required signal}) async => 'old');
          final newer = weatherTool((_, {required signal}) async => 'new');
          await client.registerTool(old);
          await client.registerTool(newer);

          await client.unregisterTool(newer);

          expect(client.state.tools, {'showWeather': old});
          await client.unregisterTool(old);
          expect(client.state.tools, isEmpty);
        },
      );

      test(
        'registering the same instance again makes it the active one',
        () async {
          final first = weatherTool((_, {required signal}) async => 'first');
          final second = weatherTool((_, {required signal}) async => 'second');
          await client.registerTool(first);
          await client.registerTool(second);

          await client.registerTool(first);

          expect(client.state.tools, {'showWeather': first});
          expect(client.state.registrations['showWeather'], [second, first]);
        },
      );

      test(
        'unregistering a tool that was never registered does nothing',
        () async {
          final tool = weatherTool((_, {required signal}) async => '');
          final other = weatherTool((_, {required signal}) async => '');
          await client.registerTool(tool);

          await client.unregisterTool(other);

          expect(client.state.tools, {'showWeather': tool});
        },
      );
    });
  });
}
