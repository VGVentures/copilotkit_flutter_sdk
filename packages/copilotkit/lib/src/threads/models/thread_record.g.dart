// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreadRecord _$ThreadRecordFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ThreadRecord', json, ($checkedConvert) {
  final val = ThreadRecord(
    id: $checkedConvert('id', (v) => v as String),
    agentId: $checkedConvert('agentId', (v) => v as String),
    archived: $checkedConvert('archived', (v) => v as bool),
    createdAt: $checkedConvert('createdAt', (v) => DateTime.parse(v as String)),
    updatedAt: $checkedConvert('updatedAt', (v) => DateTime.parse(v as String)),
    name: $checkedConvert('name', (v) => v as String?),
  );
  return val;
});
