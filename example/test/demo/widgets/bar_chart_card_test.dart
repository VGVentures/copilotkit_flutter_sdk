import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/demo/models/bar_chart_args.dart';
import 'package:example/demo/models/chart_bar.dart';
import 'package:example/demo/widgets/bar_chart_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(BarChartCard, () {
    Future<void> pump(
      WidgetTester tester, {
      BarChartArgs? args,
      ToolCallStatus status = ToolCallStatus.complete,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarChartCard(
            call: ToolCallView(id: 'c1', name: 'showBarChart', status: status),
            args: args,
          ),
        ),
      ),
    );

    List<double?> fills(WidgetTester tester) => [
      for (final bar in tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      ))
        bar.value,
    ];

    testWidgets('shows a loading bar while no bar has arrived', (tester) async {
      await pump(tester, status: ToolCallStatus.inProgress);

      expect(find.text('Chart'), findsOneWidget);
      expect(fills(tester), [null]);
    });

    testWidgets('draws each bar relative to the largest', (tester) async {
      await pump(
        tester,
        args: const BarChartArgs(
          title: 'Sales',
          bars: [
            ChartBar(label: 'Q1', value: 5),
            ChartBar(label: 'Q2', value: 10),
            ChartBar(label: 'Q3', value: 2.5),
          ],
        ),
      );

      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('2.5'), findsOneWidget);
      expect(fills(tester), [0.5, 1, 0.25]);
    });

    testWidgets('skips bars that are still streaming in', (tester) async {
      await pump(
        tester,
        status: ToolCallStatus.inProgress,
        args: const BarChartArgs(
          bars: [
            ChartBar(label: 'Q1', value: 4),
            ChartBar(label: 'Q2'),
          ],
        ),
      );

      expect(find.text('Q2'), findsNothing);
      expect(fills(tester), [1]);
    });

    testWidgets('draws empty bars when every value is zero', (tester) async {
      await pump(
        tester,
        args: const BarChartArgs(bars: [ChartBar(label: 'Q1', value: 0)]),
      );

      expect(fills(tester), [0]);
    });
  });
}
