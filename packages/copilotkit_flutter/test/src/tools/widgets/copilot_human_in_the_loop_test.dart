import 'package:ack/ack.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/recording_client.dart';

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

HumanInTheLoopTool<Map<String, Object?>> _tool() {
  return HumanInTheLoopTool(
    name: 'confirmAction',
    description: 'Ask the user to confirm an action',
    parameters: Ack.object({'action': Ack.string()}),
    decode: Map<String, Object?>.of,
  );
}

ToolCallView _call({
  ToolCallStatus status = ToolCallStatus.executing,
  bool awaitingResponse = false,
}) => ToolCallView(
  id: 'c1',
  name: 'confirmAction',
  status: status,
  args: const {'action': 'delete'},
  awaitingResponse: awaitingResponse,
);

void main() {
  group(CopilotHumanInTheLoop, () {
    late RecordingClient client;

    ClientCall registered(ClientTool<Object?> tool) =>
        ClientCall('registerTool', [tool]);
    ClientCall unregistered(ClientTool<Object?> tool) =>
        ClientCall('unregisterTool', [tool]);

    setUp(() => client = RecordingClient());

    Widget build({
      required HumanInTheLoopTool<Map<String, Object?>> tool,
      required HumanInTheLoopWidgetBuilder<Map<String, Object?>> builder,
      ToolCallView? call,
    }) {
      return CopilotKit.value(
        client: client,
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

    HumanInTheLoopWidgetBuilder<Map<String, Object?>> text() {
      return (context, call, args, respond) =>
          Text('${call.status.name} ${respond == null ? 'locked' : 'open'}');
    }

    testWidgets('registers the tool on mount and unregisters it on dispose', (
      tester,
    ) async {
      final tool = _tool();

      await tester.pumpWidget(build(tool: tool, builder: text()));
      await tester.pumpWidget(
        CopilotKit.value(client: client, child: const SizedBox()),
      );

      expect(client.calls, [registered(tool), unregistered(tool)]);
    });

    testWidgets('passes the decoded args to the builder', (tester) async {
      Map<String, Object?>? received;
      await tester.pumpWidget(
        build(
          tool: _tool(),
          builder: (context, call, args, respond) {
            received = args;
            return const SizedBox();
          },
          call: _call(),
        ),
      );

      expect(received, const {'action': 'delete'});
    });

    group('respond', () {
      testWidgets('is null unless the call awaits a response', (tester) async {
        Future<void> pump(ToolCallView call) => tester.pumpWidget(
          build(tool: _tool(), builder: text(), call: call),
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
        ToolCallResponder? respond;
        await tester.pumpWidget(
          build(
            tool: _tool(),
            builder: (context, call, args, responder) {
              respond = responder;
              return const SizedBox();
            },
            call: _call(awaitingResponse: true),
          ),
        );

        respond!({'decision': 'approve'});

        expect(
          client.calls,
          contains(
            const ClientCall('respondToToolCall', [
              'c1',
              {'decision': 'approve'},
            ]),
          ),
        );
      });

      testWidgets('keeps the card state while the call changes status', (
        tester,
      ) async {
        Widget card(
          BuildContext context,
          ToolCallView call,
          Map<String, Object?>? args,
          ToolCallResponder? respond,
        ) => _Counter(respond: respond);
        Future<void> pump(ToolCallView call) =>
            tester.pumpWidget(build(tool: _tool(), builder: card, call: call));

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
          builder: (_, _, _, _) => const Text('first'),
          call: call,
        ),
      );
      await tester.pumpWidget(
        build(
          tool: tool,
          builder: (_, _, _, _) => const Text('second'),
          call: call,
        ),
      );

      expect(find.text('second'), findsOneWidget);
    });
  });
}
