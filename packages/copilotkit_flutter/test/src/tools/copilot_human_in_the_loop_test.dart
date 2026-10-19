import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitBloc extends Mock implements CopilotKitBloc;

/// A card with state of its own: how many times it was tapped.
class const _Counter({required final ToolCallResponder? respond})
    extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _taps++),
      child: Text('taps $_taps, ${widget.respond == null ? 'locked' : 'open'}'),
    );
  }
}

HumanInTheLoopTool _tool({String name = 'confirmAction', String? description}) {
  return HumanInTheLoopTool(
    name: name,
    description: description ?? 'Ask the user to confirm an action',
    parameters: Ack.object({'action': Ack.string()}),
  );
}

ToolCallView _call({
  ToolCallStatus status = ToolCallStatus.executing,
  bool awaitingResponse = false,
}) => ToolCallView(
  id: 'c1',
  name: 'confirmAction',
  status: status,
  awaitingResponse: awaitingResponse,
);

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotHumanInTheLoop, () {
    late _MockCopilotKitBloc client;

    /// The events added to [mock], in order.
    List<CopilotKitEvent> eventsOf(_MockCopilotKitBloc mock) =>
        verify(() => mock.add(captureAny())).captured.cast<CopilotKitEvent>();

    setUp(() => client = _MockCopilotKitBloc());

    Widget build({
      required HumanInTheLoopTool tool,
      required HumanInTheLoopWidgetBuilder builder,
      ToolCallView? call,
      CopilotKitBloc? withClient,
    }) {
      return CopilotKit.value(
        client: withClient ?? client,
        child: MaterialApp(
          home: CopilotHumanInTheLoop(
            tool: tool,
            builder: builder,
            child: call == null
                ? const SizedBox()
                : Material(child: ToolCallWidget(call: call)),
          ),
        ),
      );
    }

    HumanInTheLoopWidgetBuilder text(List<ToolCallResponder?> responders) {
      return (context, call, respond) {
        responders.add(respond);
        return Text(
          '${call.status.name} ${respond == null ? 'locked' : 'open'}',
        );
      };
    }

    testWidgets('registers the tool on mount and unregisters it on dispose', (
      tester,
    ) async {
      final tool = _tool();

      await tester.pumpWidget(build(tool: tool, builder: text([])));
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(eventsOf(client), [ToolRegistered(tool), ToolUnregistered(tool)]);
    });

    testWidgets('registers a different tool before unregistering the old one', (
      tester,
    ) async {
      final first = _tool();
      final second = _tool(description: 'Another description');

      await tester.pumpWidget(build(tool: first, builder: text([])));
      await tester.pumpWidget(build(tool: second, builder: text([])));

      expect(eventsOf(client), [
        ToolRegistered(first),
        ToolRegistered(second),
        ToolUnregistered(first),
      ]);
    });

    testWidgets('does nothing when an equal tool replaces the registered one', (
      tester,
    ) async {
      final first = _tool();

      await tester.pumpWidget(build(tool: first, builder: text([])));
      await tester.pumpWidget(build(tool: _tool(), builder: text([])));

      expect(eventsOf(client), [ToolRegistered(first)]);
    });

    testWidgets('moves the tool when the client changes', (tester) async {
      final other = _MockCopilotKitBloc();
      final tool = _tool();

      await tester.pumpWidget(build(tool: tool, builder: text([])));
      await tester.pumpWidget(
        build(tool: tool, builder: text([]), withClient: other),
      );

      expect(eventsOf(client), [ToolRegistered(tool), ToolUnregistered(tool)]);
      expect(eventsOf(other), [ToolRegistered(tool)]);
    });

    group('respond', () {
      testWidgets('is null unless the call awaits a response', (tester) async {
        final responders = <ToolCallResponder?>[];
        Future<void> pump(ToolCallView call) => tester.pumpWidget(
          build(tool: _tool(), builder: text(responders), call: call),
        );

        await pump(_call(status: ToolCallStatus.inProgress));
        expect(find.text('inProgress locked'), findsOneWidget);

        await pump(_call());
        expect(find.text('executing locked'), findsOneWidget);

        await pump(_call(awaitingResponse: true));
        expect(find.text('executing open'), findsOneWidget);

        await pump(_call(status: ToolCallStatus.complete));
        expect(find.text('complete locked'), findsOneWidget);
      });

      testWidgets('answers the call on the client', (tester) async {
        late ToolCallResponder respond;
        await tester.pumpWidget(
          build(
            tool: _tool(),
            builder: (context, call, responder) {
              respond = responder ?? (_) {};
              return const SizedBox();
            },
            call: _call(awaitingResponse: true),
          ),
        );

        respond({'decision': 'approve'});

        expect(
          eventsOf(client),
          contains(const ToolCallResponded('c1', {'decision': 'approve'})),
        );
      });

      testWidgets('keeps the card state while the call changes status', (
        tester,
      ) async {
        HumanInTheLoopWidgetBuilder card() =>
            (context, call, respond) => _Counter(respond: respond);
        final builder = card();
        Future<void> pump(ToolCallView call) => tester.pumpWidget(
          build(tool: _tool(), builder: builder, call: call),
        );

        await pump(_call(status: ToolCallStatus.inProgress));
        await tester.tap(find.byType(TextButton));
        await tester.pump();
        expect(find.text('taps 1, locked'), findsOneWidget);

        await pump(_call());
        await pump(_call(awaitingResponse: true));
        expect(find.text('taps 1, open'), findsOneWidget);

        await tester.tap(find.byType(TextButton));
        await tester.pump();
        await pump(_call(status: ToolCallStatus.complete));
        expect(find.text('taps 2, locked'), findsOneWidget);
      });
    });

    testWidgets('renders with a new builder when it changes', (tester) async {
      final tool = _tool();
      final call = _call(awaitingResponse: true);

      await tester.pumpWidget(
        build(
          tool: tool,
          builder: (_, _, _) => const Text('first'),
          call: call,
        ),
      );
      await tester.pumpWidget(
        build(
          tool: tool,
          builder: (_, _, _) => const Text('second'),
          call: call,
        ),
      );

      expect(find.text('second'), findsOneWidget);
    });
  });
}
