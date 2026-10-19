import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotComponent, () {
    late _MockCopilotKitBloc client;

    /// The events added to [mock], in order.
    List<CopilotKitEvent> eventsOf(_MockCopilotKitBloc mock) =>
        verify(() => mock.add(captureAny())).captured.cast<CopilotKitEvent>();

    setUp(() => client = _MockCopilotKitBloc());

    final parameters = Ack.object({'city': Ack.string()});

    Widget build({
      String? description,
      String? agentId,
      ToolCallView? call,
      ComponentWidgetBuilder? builder,
    }) {
      return CopilotKit.value(
        client: client,
        child: MaterialApp(
          home: CopilotComponent(
            name: 'weatherCard',
            parameters: parameters,
            description: description,
            agentId: agentId,
            builder:
                builder ??
                (context, args, status) =>
                    Text('${args['city']} ${status.name}'),
            child: call == null ? const SizedBox() : ToolCallWidget(call: call),
          ),
        ),
      );
    }

    testWidgets(
      'registers a component tool on mount and removes it on dispose',
      (tester) async {
        await tester.pumpWidget(
          build(description: 'Shows the forecast.', agentId: 'ops'),
        );
        await tester.pumpWidget(
          CopilotKit.value(client: client, child: const SizedBox()),
        );

        final [registered, unregistered] = eventsOf(client);
        final tool = (registered as ToolRegistered).tool as ComponentTool;
        expect(tool.name, 'weatherCard');
        expect(tool.parameters, same(parameters));
        expect(tool.agentId, 'ops');
        expect(
          tool.description,
          startsWith(
            'Use this tool to display the "weatherCard" component in the chat. '
            'This tool renders a visual UI component for the user.',
          ),
        );
        expect(tool.description, endsWith('\n\nShows the forecast.'));
        expect(unregistered, ToolUnregistered(tool));
      },
    );

    testWidgets('keeps the registration across rebuilds', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpWidget(build());

      expect(eventsOf(client), hasLength(1));
    });

    testWidgets('registers the new tool when its description changes', (
      tester,
    ) async {
      await tester.pumpWidget(build());
      await tester.pumpWidget(build(description: 'Now with a description.'));

      final events = eventsOf(client);
      expect(events, hasLength(3));
      expect(events[0], isA<ToolRegistered>());
      expect(events[1], isA<ToolRegistered>());
      expect(events[2], isA<ToolUnregistered>());
    });

    testWidgets('builds every call with its arguments and status', (
      tester,
    ) async {
      Future<void> pump(ToolCallStatus status) => tester.pumpWidget(
        build(
          call: ToolCallView(
            id: 'c1',
            name: 'weatherCard',
            status: status,
            args: const {'city': 'Lima'},
          ),
        ),
      );

      await pump(ToolCallStatus.inProgress);
      expect(find.text('Lima inProgress'), findsOneWidget);

      await pump(ToolCallStatus.complete);
      expect(find.text('Lima complete'), findsOneWidget);
    });
  });
}
