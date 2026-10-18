import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

FrontendTool _tool(
  String name, {
  String description = 'A tool',
  ObjectSchema? parameters,
  FrontendToolHandler? handler,
}) => FrontendTool(
  name: name,
  description: description,
  parameters: parameters ?? Ack.object({}),
  handler: handler ?? (args, {required signal}) async => 'ok',
);

const _call = ToolCallView(
  id: 'c1',
  name: 'showWeather',
  status: ToolCallStatus.executing,
);

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotTool, () {
    late _MockCopilotKitClient client;

    /// The events added to [mock], in order.
    List<CopilotKitEvent> eventsOf(_MockCopilotKitClient mock) =>
        verify(() => mock.add(captureAny())).captured.cast<CopilotKitEvent>();

    /// The events of [mock] as `+name` for a registration and `-name` for a
    /// removal.
    List<String> summaryOf(_MockCopilotKitClient mock) => [
      for (final event in eventsOf(mock))
        switch (event) {
          ToolRegistered(:final tool) => '+${tool.name}',
          ToolUnregistered(:final tool) => '-${tool.name}',
          _ => event.toString(),
        },
    ];

    setUp(() => client = _MockCopilotKitClient());

    testWidgets('registers the tool on mount', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(
            tool: _tool('showWeather'),
            child: const SizedBox(),
          ),
        ),
      );

      expect(summaryOf(client), ['+showWeather']);
    });

    testWidgets('unregisters the tool on dispose', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(
            tool: _tool('showWeather'),
            child: const SizedBox(),
          ),
        ),
      );

      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(summaryOf(client), ['+showWeather', '-showWeather']);
    });

    testWidgets('unregisters the instance it registered', (tester) async {
      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(
            tool: _tool('showWeather'),
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      final events = eventsOf(client);

      expect(
        (events[0] as ToolRegistered).tool,
        (events[1] as ToolUnregistered).tool,
      );
    });

    group('when the parent rebuilds', () {
      Widget build(CopilotKitClient client, FrontendTool tool) =>
          CopilotKit.value(
            client: client,
            child: CopilotTool(tool: tool, child: const SizedBox()),
          );

      testWidgets('keeps the registration for an equivalent new tool', (
        tester,
      ) async {
        await tester.pumpWidget(build(client, _tool('showWeather')));
        await tester.pumpWidget(build(client, _tool('showWeather')));
        await tester.pumpWidget(build(client, _tool('showWeather')));

        expect(summaryOf(client), ['+showWeather']);
      });

      testWidgets('re-registers when the name changes', (tester) async {
        await tester.pumpWidget(build(client, _tool('first')));
        await tester.pumpWidget(build(client, _tool('second')));

        expect(summaryOf(client), ['+first', '-first', '+second']);
      });

      testWidgets('re-registers when the description changes', (tester) async {
        await tester.pumpWidget(build(client, _tool('t')));
        await tester.pumpWidget(
          build(client, _tool('t', description: 'Something else')),
        );

        expect(summaryOf(client), ['+t', '-t', '+t']);
      });

      testWidgets('re-registers when the parameters change', (tester) async {
        await tester.pumpWidget(build(client, _tool('t')));
        await tester.pumpWidget(
          build(
            client,
            _tool('t', parameters: Ack.object({'city': Ack.string()})),
          ),
        );

        expect(summaryOf(client), ['+t', '-t', '+t']);
      });

      testWidgets('calls run the handler of the latest widget', (tester) async {
        await tester.pumpWidget(
          build(
            client,
            _tool('t', handler: (args, {required signal}) async => 'old'),
          ),
        );
        await tester.pumpWidget(
          build(
            client,
            _tool('t', handler: (args, {required signal}) async => 'new'),
          ),
        );

        final registered = (eventsOf(client).single as ToolRegistered).tool;
        final result = await registered.handler(
          const {},
          signal: CancellationSignal(),
        );

        expect(result, 'new');
      });
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = _MockCopilotKitClient();
      final tool = _tool('showWeather');
      Widget build(CopilotKitClient c) => CopilotKit.value(
        client: c,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(client));
      await tester.pumpWidget(build(other));

      expect(summaryOf(client), ['+showWeather', '-showWeather']);
      expect(summaryOf(other), ['+showWeather']);
    });

    testWidgets('keeps the tool while a duplicate of it is unmounted', (
      tester,
    ) async {
      final real = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
      );
      addTearDown(real.close);
      Widget build({required bool duplicate}) => CopilotKit.value(
        client: real,
        child: CopilotTool(
          tool: _tool('showWeather'),
          child: duplicate
              ? CopilotTool(tool: _tool('showWeather'), child: const SizedBox())
              : const SizedBox(),
        ),
      );

      await tester.pumpWidget(build(duplicate: true));
      await tester.pumpWidget(build(duplicate: false));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(real.state.tools.keys, ['showWeather']);
    });

    group('builder', () {
      Widget app(Widget child) => CopilotKit.value(
        client: client,
        child: MaterialApp(home: child),
      );

      testWidgets('renders its calls inside its child', (tester) async {
        await tester.pumpWidget(
          app(
            CopilotTool(
              tool: _tool('showWeather'),
              builder: (context, call) => Text('weather ${call.status.name}'),
              child: ToolCallWidget(call: _call),
            ),
          ),
        );

        expect(find.text('weather executing'), findsOneWidget);
      });

      testWidgets('does not render calls outside its child', (tester) async {
        await tester.pumpWidget(
          app(
            Column(
              children: [
                CopilotTool(
                  tool: _tool('showWeather'),
                  builder: (context, call) => const Text('weather'),
                  child: const SizedBox(),
                ),
                ToolCallWidget(call: _call),
              ],
            ),
          ),
        );

        expect(find.text('weather'), findsNothing);
      });

      testWidgets('calls the builder of the current widget', (tester) async {
        Widget build(String label) => app(
          CopilotTool(
            tool: _tool('showWeather'),
            builder: (context, call) => Text(label),
            child: ToolCallWidget(call: _call),
          ),
        );

        await tester.pumpWidget(build('one'));
        await tester.pumpWidget(build('two'));

        expect(find.text('two'), findsOneWidget);
      });

      testWidgets('without a builder leaves rendering to other renderers', (
        tester,
      ) async {
        await tester.pumpWidget(
          app(
            ToolRenderer(
              name: ToolRenderer.nameFallback,
              builder: (context, call) => const Text('generic'),
              child: CopilotTool(
                tool: _tool('showWeather'),
                child: ToolCallWidget(call: _call),
              ),
            ),
          ),
        );

        expect(find.text('generic'), findsOneWidget);
      });
    });
  });
}
