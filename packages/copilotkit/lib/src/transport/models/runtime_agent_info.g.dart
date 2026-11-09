// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_agent_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RuntimeAgentInfo _$RuntimeAgentInfoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RuntimeAgentInfo', json, ($checkedConvert) {
      final val = RuntimeAgentInfo(
        name: $checkedConvert('name', (v) => v as String? ?? ''),
        description: $checkedConvert('description', (v) => v as String? ?? ''),
      );
      return val;
    });
