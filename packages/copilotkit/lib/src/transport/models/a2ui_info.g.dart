// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'a2ui_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

A2uiInfo _$A2uiInfoFromJson(Map<String, dynamic> json) => $checkedCreate(
  'A2uiInfo',
  json,
  ($checkedConvert) {
    final val = A2uiInfo(
      agents: $checkedConvert(
        'agents',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
    );
    return val;
  },
);
