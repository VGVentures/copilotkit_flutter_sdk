import 'package:example/demo/models/bar_chart_args.dart';
import 'package:example/demo/models/chart_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(BarChartArgs, () {
    test('decodes the title and the bars', () {
      final args = BarChartArgs.fromJson({
        'title': 'Sales',
        'bars': [
          {'label': 'Q1', 'value': 3},
        ],
      });

      expect(args.title, 'Sales');
      expect(args.bars?.single.label, 'Q1');
    });

    test('allows missing fields while they stream in', () {
      final args = BarChartArgs.fromJson({});

      expect(args.title, isNull);
      expect(args.bars, isNull);
    });

    test('encodes to JSON', () {
      expect(
        const BarChartArgs(
          title: 'Sales',
          bars: [ChartBar(label: 'Q1', value: 3)],
        ).toJson(),
        {
          'title': 'Sales',
          'bars': [
            {'label': 'Q1', 'value': 3.0},
          ],
        },
      );
    });
  });
}
