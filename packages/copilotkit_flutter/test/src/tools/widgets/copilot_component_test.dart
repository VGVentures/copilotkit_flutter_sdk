import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

void main() {
  group(CopilotComponent, () {
    late RecordingClient client;
    final parameters = Ack.object({'title': Ack.string()});

    String? decodeTitle(Map<String, Object?> json) => json['title'] as String?;

    setUp(() => client = RecordingClient());

    CopilotComponent<String?> component({
      bool followUp = true,
      Widget child = const SizedBox(),
    }) => CopilotComponent<String?>(
      name: 'barChart',
      description: 'Shows a bar chart.',
      parameters: parameters,
      decode: decodeTitle,
      followUp: followUp,
      builder: (context, call, title) => Text('chart: $title'),
      child: child,
    );

    List<FrontendTool<Object?>> registered() => [
      for (final call in client.calls)
        if (call.method == 'registerTool')
          call.arguments.single! as FrontendTool<Object?>,
    ];

    testWidgets('registers a tool without a handler and with the prefix', (
      tester,
    ) async {
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: component()),
      );

      final tool = registered().single;
      expect(tool.name, 'barChart');
      expect(
        tool.description,
        'Use this tool to display the "barChart" component in the chat. '
        'This tool renders a visual UI component for the user. '
        'Shows a bar chart.',
      );
      expect(tool.parameters, same(parameters));
      expect(tool.handler, isNull);
      expect(tool.followUp, isTrue);
    });

    testWidgets('passes followUp to the tool', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: component(followUp: false)),
      );

      expect(registered().single.followUp, isFalse);
    });

    testWidgets('unregisters the tool on dispose', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: component()),
      );
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(client.calls.map((call) => call.method), [
        'registerTool',
        'unregisterTool',
      ]);
    });

    testWidgets('renders calls with the decoded, possibly partial, args', (
      tester,
    ) async {
      Widget build(Map<String, Object?> args) => CopilotKit.value(
        client: client,
        child: MaterialApp(
          home: component(
            child: ToolCallWidget(
              call: ToolCallView(
                id: 'c1',
                name: 'barChart',
                status: ToolCallStatus.inProgress,
                args: args,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(const {}));
      expect(find.text('chart: null'), findsOneWidget);

      await tester.pumpWidget(build(const {'title': 'Sales'}));
      expect(find.text('chart: Sales'), findsOneWidget);
    });
  });
}
