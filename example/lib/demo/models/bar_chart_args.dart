import 'package:example/demo/models/chart_bar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'bar_chart_args.g.dart';

/// Arguments of the `showBarChart` component.
///
/// Mirrors the component's Ack schema in `bar_chart_demo.dart`; keep both in
/// sync. Every field is nullable, unlike in the schema, because
/// `BarChartCard` also reads the partial args streamed before the call
/// completes.
@JsonSerializable()
class const BarChartArgs({final String? title, final List<ChartBar>? bars}) {
  factory fromJson(Map<String, Object?> json) => _$BarChartArgsFromJson(json);

  Map<String, Object?> toJson() => _$BarChartArgsToJson(this);
}
