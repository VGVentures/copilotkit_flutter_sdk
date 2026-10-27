import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

FrontendTool<Map<String, Object?>> _tool(String name) => FrontendTool(
  name: name,
  description: 'A tool',
  parameters: Ack.object({}),
  decode: Map<String, Object?>.of,
  handler: (args, {required signal}) async => 'ok',
);

void main() {
  group(CopilotTool, () {
    late RecordingClient client;

    ClientCall registered(ClientTool<Object?> tool) =>
        ClientCall('registerTool', [tool]);
    ClientCall unregistered(ClientTool<Object?> tool) =>
        ClientCall('unregisterTool', [tool]);

    setUp(() => client = RecordingClient());

    testWidgets('registers the tool on mount and unregisters it on dispose', (
      tester,
    ) async {
      final tool = _tool('showWeather');

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(tool: tool, child: const SizedBox()),
        ),
      );
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(client.calls, [registered(tool), unregistered(tool)]);
    });

    testWidgets('renders its calls with its builder', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: CopilotTool(
              tool: _tool('showWeather'),
              builder: (context, call, args) =>
                  Text('weather ${call.status.name}'),
              child: ToolCallWidget(
                call: const ToolCallView(
                  id: 'c1',
                  name: 'showWeather',
                  status: ToolCallStatus.executing,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('weather executing'), findsOneWidget);
    });

    testWidgets('passes the builder the args decoded by the tool', (
      tester,
    ) async {
      final tool = FrontendTool<String>(
        name: 'showWeather',
        description: 'A tool',
        parameters: Ack.object({'city': Ack.string()}),
        decode: (json) => json['city']! as String,
        handler: (city, {required signal}) async => 'ok',
      );
      Widget build(Map<String, Object?> args) => CopilotKit.value(
        client: client,
        child: MaterialApp(
          home: CopilotTool(
            tool: tool,
            builder: (context, call, city) => Text('city: $city'),
            child: ToolCallWidget(
              call: ToolCallView(
                id: 'c1',
                name: 'showWeather',
                status: ToolCallStatus.inProgress,
                args: args,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(const <String, Object?>{}));
      expect(find.text('city: null'), findsOneWidget);

      await tester.pumpWidget(build(const {'city': 'Lima'}));
      expect(find.text('city: Lima'), findsOneWidget);
    });

    testWidgets('without a builder leaves rendering to other renderers', (
      tester,
    ) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: ToolRenderer(
              name: ToolRenderer.nameFallback,
              builder: (context, call) => const Text('generic'),
              child: CopilotTool(
                tool: _tool('showWeather'),
                child: ToolCallWidget(
                  call: const ToolCallView(
                    id: 'c1',
                    name: 'showWeather',
                    status: ToolCallStatus.inProgress,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('generic'), findsOneWidget);
    });
  });
}
