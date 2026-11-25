import 'package:example/demo/models/chart_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

void main() {
  group(ChartBar, () {
    test('decodes a label and a value', () {
      final bar = ChartBar.fromJson({'label': 'Q1', 'value': 12});

      expect(bar.label, 'Q1');
      expect(bar.value, 12);
    });

    test('allows missing fields while they stream in', () {
      final bar = ChartBar.fromJson({});

      expect(bar.label, isNull);
      expect(bar.value, isNull);
    });

    test('rejects a value that is not a number', () {
      expect(
        () => ChartBar.fromJson({'value': 'twelve'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('encodes to JSON', () {
      expect(const ChartBar(label: 'Q1', value: 1.5).toJson(), {
        'label': 'Q1',
        'value': 1.5,
      });
    });
  });
}
