// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RuntimeInfo _$RuntimeInfoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RuntimeInfo', json, ($checkedConvert) {
      final val = RuntimeInfo(
        version: $checkedConvert('version', (v) => v as String? ?? ''),
        mode: $checkedConvert(
          'mode',
          (v) =>
              $enumDecodeNullable(
                _$RuntimeModeEnumMap,
                v,
                unknownValue: RuntimeMode.sse,
              ) ??
              RuntimeMode.sse,
        ),
        intelligence: $checkedConvert(
          'intelligence',
          (v) => v == null
              ? null
              : IntelligenceInfo.fromJson(v as Map<String, dynamic>),
        ),
        threadEndpoints: $checkedConvert(
          'threadEndpoints',
          (v) => v == null
              ? const ThreadEndpoints()
              : ThreadEndpoints.fromJson(v as Map<String, dynamic>),
        ),
        a2uiEnabled: $checkedConvert('a2uiEnabled', (v) => v as bool? ?? false),
        a2ui: $checkedConvert(
          'a2ui',
          (v) =>
              v == null ? null : A2uiInfo.fromJson(v as Map<String, dynamic>),
        ),
        agents: $checkedConvert(
          'agents',
          (v) =>
              (v as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(
                  k,
                  RuntimeAgentInfo.fromJson(e as Map<String, dynamic>),
                ),
              ) ??
              const {},
        ),
      );
      return val;
    });

const _$RuntimeModeEnumMap = {
  RuntimeMode.sse: 'sse',
  RuntimeMode.intelligence: 'intelligence',
};
