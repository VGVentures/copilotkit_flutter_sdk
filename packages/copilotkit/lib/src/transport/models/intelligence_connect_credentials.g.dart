// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intelligence_connect_credentials.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IntelligenceConnectCredentials _$IntelligenceConnectCredentialsFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IntelligenceConnectCredentials', json, ($checkedConvert) {
  final val = IntelligenceConnectCredentials(
    threadId: $checkedConvert('threadId', (v) => v as String),
    joinToken: $checkedConvert('joinToken', (v) => v as String),
    realtime: $checkedConvert(
      'realtime',
      (v) => IntelligenceRealtime.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});
