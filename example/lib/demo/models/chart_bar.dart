import 'package:json_annotation/json_annotation.dart';

part 'chart_bar.g.dart';

/// One bar of a `showBarChart` call.
///
/// Both fields are nullable because the card also reads the partial args
/// streamed before the call completes.
@JsonSerializable()
class const ChartBar({final String? label, final double? value}) {
  factory fromJson(Map<String, Object?> json) => _$ChartBarFromJson(json);

  Map<String, Object?> toJson() => _$ChartBarToJson(this);
}
