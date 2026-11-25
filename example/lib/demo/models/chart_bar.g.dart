// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chart_bar.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChartBar _$ChartBarFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChartBar', json, ($checkedConvert) {
      final val = ChartBar(
        label: $checkedConvert('label', (v) => v as String?),
        value: $checkedConvert('value', (v) => (v as num?)?.toDouble()),
      );
      return val;
    });

Map<String, dynamic> _$ChartBarToJson(ChartBar instance) => <String, dynamic>{
  'label': ?instance.label,
  'value': ?instance.value,
};
