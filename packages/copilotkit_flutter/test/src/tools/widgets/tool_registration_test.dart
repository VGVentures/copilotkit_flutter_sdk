import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:copilotkit_flutter/src/tools/widgets/tool_registration.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

Future<String> _handler(
  Map<String, Object?> args, {
  required CancellationSignal signal,
}) async => 'ok';

FrontendTool<Map<String, Object?>> _tool(String name) => FrontendTool(
  name: name,
  description: 'A tool',
  parameters: Ack.object({}),
  decode: Map<String, Object?>.of,
  handler: _handler,
);

void main() {
  group(ToolRegistration, () {
    late RecordingClient client;

    ClientCall registered(ClientTool<Object?> tool) =>
        ClientCall('registerTool', [tool]);
    ClientCall unregistered(ClientTool<Object?> tool) =>
        ClientCall('unregisterTool', [tool]);

    setUp(() => client = RecordingClient());

    Widget build(ClientTool<Object?> tool, {CopilotKitClient? withClient}) =>
        CopilotKit.value(
          client: withClient ?? client,
          child: ToolRegistration(tool: tool, child: const SizedBox()),
        );

    testWidgets('registers the tool on mount', (tester) async {
      final tool = _tool('showWeather');

      await tester.pumpWidget(build(tool));

      expect(client.calls, [registered(tool)]);
    });

    testWidgets('unregisters the tool on dispose', (tester) async {
      final tool = _tool('showWeather');
      await tester.pumpWidget(build(tool));

      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(client.calls, [registered(tool), unregistered(tool)]);
    });

    testWidgets('registers a different tool before unregistering the old one', (
      tester,
    ) async {
      final first = _tool('first');
      final second = _tool('second');

      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(second));

      // The new tool first, so the client never lacks the tool in between.
      expect(client.calls, [
        registered(first),
        registered(second),
        unregistered(first),
      ]);
    });

    testWidgets('keeps the registration when an equal tool replaces it', (
      tester,
    ) async {
      final first = _tool('showWeather');

      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(_tool('showWeather')));
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(client.calls, [registered(first), unregistered(first)]);
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = RecordingClient();
      final tool = _tool('showWeather');

      await tester.pumpWidget(build(tool));
      await tester.pumpWidget(build(tool, withClient: other));

      expect(client.calls, [registered(tool), unregistered(tool)]);
      expect(other.calls, [registered(tool)]);
    });

    group('with a real client', () {
      late CopilotKitClient realClient;

      setUp(
        () => realClient = CopilotKitClient(
          runtimeUrl: Uri.parse('http://runtime.test'),
        ),
      );

      tearDown(() => realClient.close());

      testWidgets('keeps the tool when its subtree remounts', (tester) async {
        final tool = _tool('showWeather');
        Widget build(Key key) => CopilotKit.value(
          client: realClient,
          child: ToolRegistration(
            key: key,
            tool: tool,
            child: const SizedBox(),
          ),
        );

        await tester.pumpWidget(build(const ValueKey(1)));
        await tester.pumpWidget(build(const ValueKey(2)));

        expect(realClient.tools, {'showWeather': tool});
      });

      testWidgets('keeps a shared tool until its last owner is removed', (
        tester,
      ) async {
        final tool = _tool('showWeather');
        Widget build({required bool both}) => CopilotKit.value(
          client: realClient,
          child: Column(
            children: [
              ToolRegistration(tool: tool, child: const SizedBox()),
              if (both) ToolRegistration(tool: tool, child: const SizedBox()),
            ],
          ),
        );

        await tester.pumpWidget(build(both: true));
        await tester.pumpWidget(build(both: false));
        expect(realClient.tools, {'showWeather': tool});

        await tester.pumpWidget(
          CopilotKit.value(client: realClient, child: const SizedBox()),
        );
        expect(realClient.tools, isEmpty);
      });
    });
  });
}
