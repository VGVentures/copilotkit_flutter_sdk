// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bar_chart_args.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BarChartArgs _$BarChartArgsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('BarChartArgs', json, ($checkedConvert) {
      final val = BarChartArgs(
        title: $checkedConvert('title', (v) => v as String?),
        bars: $checkedConvert(
          'bars',
          (v) => (v as List<dynamic>?)
              ?.map((e) => ChartBar.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$BarChartArgsToJson(BarChartArgs instance) =>
    <String, dynamic>{
      'title': ?instance.title,
      'bars': ?instance.bars?.map((e) => e.toJson()).toList(),
    };
