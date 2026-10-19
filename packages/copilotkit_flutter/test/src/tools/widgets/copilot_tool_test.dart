import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

FrontendTool _tool(String name) => FrontendTool(
  name: name,
  description: 'A tool',
  parameters: Ack.object({}),
  handler: (args, {required signal}) async => 'ok',
);

void main() {
  group(CopilotTool, () {
    late RecordingClient client;

    ClientCall registered(FrontendTool tool) =>
        ClientCall('registerTool', [tool]);
    ClientCall unregistered(FrontendTool tool) =>
        ClientCall('unregisterTool', [tool]);

    setUp(() => client = RecordingClient());

    testWidgets('registers the tool on mount', (tester) async {
      final tool = _tool('showWeather');

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(tool: tool, child: const SizedBox()),
        ),
      );

      expect(client.calls, [registered(tool)]);
    });

    testWidgets('unregisters the tool on dispose', (tester) async {
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

    testWidgets('re-registers when the tool changes', (tester) async {
      final first = _tool('first');
      final second = _tool('second');
      Widget build(FrontendTool tool) => CopilotKit.value(
        client: client,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(second));

      expect(client.calls, [
        registered(first),
        unregistered(first),
        registered(second),
      ]);
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = RecordingClient();
      final tool = _tool('showWeather');
      Widget build(CopilotKitClient c) => CopilotKit.value(
        client: c,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(client));
      await tester.pumpWidget(build(other));

      expect(client.calls, [registered(tool), unregistered(tool)]);
      expect(other.calls, [registered(tool)]);
    });

    testWidgets('renders its calls with its builder', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: MaterialApp(
            home: CopilotTool(
              tool: _tool('showWeather'),
              builder: (context, call) => Text('weather ${call.status.name}'),
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
