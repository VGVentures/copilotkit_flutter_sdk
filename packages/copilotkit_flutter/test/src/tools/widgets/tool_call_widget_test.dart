import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallView _call(
  String name, {
  String id = 'c1',
  ToolCallStatus status = ToolCallStatus.inProgress,
  Map<String, Object?> args = const <String, Object?>{},
  String? result,
}) {
  return ToolCallView(
    id: id,
    name: name,
    status: status,
    args: args,
    result: result,
  );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

class const _Counter(final String label) extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('${widget.label} $_count'),
    );
  }
}

void main() {
  group(ToolCallWidget, () {
    testWidgets('renders nothing without a matching builder', (tester) async {
      await tester.pumpWidget(_app(ToolCallWidget(call: _call('unknown'))));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('keeps builder state while the call updates', (tester) async {
      Widget build(ToolCallStatus status) => _app(
        ToolRenderer(
          name: 'tool',
          builder: (context, call) => const _Counter('count'),
          child: ToolCallWidget(call: _call('tool', status: status)),
        ),
      );
      await tester.pumpWidget(build(ToolCallStatus.inProgress));
      await tester.tap(find.text('count 0'));
      await tester.pump();

      await tester.pumpWidget(build(ToolCallStatus.complete));

      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('keeps builder state when scrolled off-screen and back', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ToolRenderer(
            name: 'tool',
            builder: (context, call) => const _Counter('count'),
            child: ListView(
              children: [
                ToolCallWidget(call: _call('tool')),
                for (var i = 0; i < 50; i++)
                  SizedBox(height: 100, child: Text('row $i')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('count 0'));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.textContaining('count'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 6000));
      await tester.pumpAndSettle();

      expect(find.text('count 1'), findsOneWidget);
    });
  });
}
