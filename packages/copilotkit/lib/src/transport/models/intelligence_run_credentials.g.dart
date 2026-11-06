// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intelligence_run_credentials.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IntelligenceRunCredentials _$IntelligenceRunCredentialsFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IntelligenceRunCredentials', json, ($checkedConvert) {
  final val = IntelligenceRunCredentials(
    threadId: $checkedConvert('threadId', (v) => v as String),
    runId: $checkedConvert('runId', (v) => v as String),
    joinToken: $checkedConvert('joinToken', (v) => v as String),
    realtime: $checkedConvert(
      'realtime',
      (v) => IntelligenceRealtime.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});
