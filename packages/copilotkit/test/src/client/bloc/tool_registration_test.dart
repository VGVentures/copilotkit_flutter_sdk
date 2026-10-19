import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';
import '../../../helpers/tool_loop_harness.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('frontend tools', () {
    late ToolLoopHarness harness;
    late TestCopilotKitBloc client;
    late CopilotAgentBloc agent;
    late List<Stream<BaseEvent>> runs;

    setUp(() async {
      harness = ToolLoopHarness();
      await harness.open();
      client = harness.client;
      agent = harness.agent;
      runs = harness.runs;
    });

    List<RunAgentInput> sentInputs() => harness.transport.sentInputs();

    group('$ToolRegistered', () {
      blocTest<CopilotKitBloc, CopilotKitState>(
        'sends registered tools with their JSON Schema',
        build: () => client,
        act: (_) async {
          await client.registerTool(
            weatherTool((_, {required signal}) async => ''),
          );
          runs.add(const Stream.empty());
          await client.runAgent(agent);
        },
        verify: (_) {
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
        },
      );

      blocTest<CopilotKitBloc, CopilotKitState>(
        'sends empty properties for empty object schemas',
        build: () => client,
        act: (_) async {
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
        },
        verify: (_) => expect(sentInputs().single.tools.single.parameters, {
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
        }),
      );

      final tool = weatherTool((_, {required signal}) async => '');

      blocTest<CopilotKitBloc, CopilotKitState>(
        'ToolUnregistered removes the tool',
        build: () => client,
        act: (_) async {
          await client.registerTool(tool);
          expect(client.state.tools, {'showWeather': tool});

          await client.unregisterTool(tool);
          runs.add(const Stream.empty());
          await client.runAgent(agent);
        },
        verify: (_) {
          expect(client.state.tools, isEmpty);
          expect(sentInputs().single.tools, isEmpty);
        },
      );

      final old = weatherTool((_, {required signal}) async => 'old');
      final newer = weatherTool((_, {required signal}) async => 'new');

      blocTest<CopilotKitBloc, CopilotKitState>(
        'a stale ToolUnregistered keeps a newer tool with the same name',
        build: () => client,
        act: (_) async {
          await client.registerTool(old);
          await client.registerTool(newer);
          await client.unregisterTool(old);
          runs.add(const Stream.empty());
          await client.runAgent(agent);
        },
        verify: (_) {
          expect(client.state.tools, {'showWeather': newer});
          expect(sentInputs().single.tools, hasLength(1));
        },
      );
    });
  });
}
