import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

FrontendTool _tool(String name) => FrontendTool(
  name: name,
  description: 'A tool',
  parameters: JsonSchema.object({}),
  handler: (args, {required signal}) async => 'ok',
);

void main() {
  setUpAll(() => registerFallbackValue(_tool('fallback')));

  group(CopilotTool, () {
    late _MockCopilotKitClient client;
    late List<String> unregistered;

    _MockCopilotKitClient mockClient() {
      final mock = _MockCopilotKitClient();
      when(() => mock.registerTool(any())).thenAnswer((invocation) {
        final tool = invocation.positionalArguments.single as FrontendTool;
        return () => unregistered.add(tool.name);
      });
      return mock;
    }

    setUp(() {
      unregistered = [];
      client = mockClient();
    });

    testWidgets('registers the tool on mount', (tester) async {
      final tool = _tool('showWeather');

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(tool: tool, child: const SizedBox()),
        ),
      );

      verify(() => client.registerTool(tool)).called(1);
      expect(unregistered, isEmpty);
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

      expect(unregistered, ['showWeather']);
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

      verify(() => client.registerTool(first)).called(1);
      verify(() => client.registerTool(second)).called(1);
      expect(unregistered, ['first']);
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = mockClient();
      final tool = _tool('showWeather');
      Widget build(CopilotKitClient c) => CopilotKit.value(
        client: c,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(client));
      await tester.pumpWidget(build(other));

      expect(unregistered, ['showWeather']);
      verify(() => other.registerTool(tool)).called(1);
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
              name: '*',
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
