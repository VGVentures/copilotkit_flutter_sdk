import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

FrontendTool _tool(String name) => FrontendTool(
  name: name,
  description: 'A tool',
  parameters: Ack.object({}),
  handler: (args, {required signal}) async => 'ok',
);

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotTool, () {
    late _MockCopilotKitBloc client;

    /// The events added to [mock], in order.
    List<CopilotKitEvent> eventsOf(_MockCopilotKitBloc mock) =>
        verify(() => mock.add(captureAny())).captured.cast<CopilotKitEvent>();

    setUp(() => client = _MockCopilotKitBloc());

    testWidgets('registers the tool on mount', (tester) async {
      final tool = _tool('showWeather');

      await tester.pumpWidget(
        CopilotKit.value(
          client: client,
          child: CopilotTool(tool: tool, child: const SizedBox()),
        ),
      );

      expect(eventsOf(client), [ToolRegistered(tool)]);
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

      expect(eventsOf(client), [ToolRegistered(tool), ToolUnregistered(tool)]);
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

      // The new tool first, so the client never lacks the tool in between.
      expect(eventsOf(client), [
        ToolRegistered(first),
        ToolRegistered(second),
        ToolUnregistered(first),
      ]);
    });

    testWidgets('keeps the registration when an equal tool replaces it', (
      tester,
    ) async {
      Future<String> handler(
        Map<String, Object?> args, {
        required CancellationSignal signal,
      }) async => 'ok';
      FrontendTool tool() => FrontendTool(
        name: 'showWeather',
        description: 'A tool',
        parameters: Ack.object({}),
        handler: handler,
      );
      final first = tool();
      Widget build(FrontendTool tool) => CopilotKit.value(
        client: client,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(tool()));
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      // The client holds the first instance, so that is the one unregistered.
      expect(eventsOf(client), [
        ToolRegistered(first),
        ToolUnregistered(first),
      ]);
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = _MockCopilotKitBloc();
      final tool = _tool('showWeather');
      Widget build(CopilotKitBloc c) => CopilotKit.value(
        client: c,
        child: CopilotTool(tool: tool, child: const SizedBox()),
      );

      await tester.pumpWidget(build(client));
      await tester.pumpWidget(build(other));

      expect(eventsOf(client), [ToolRegistered(tool), ToolUnregistered(tool)]);
      expect(eventsOf(other), [ToolRegistered(tool)]);
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
