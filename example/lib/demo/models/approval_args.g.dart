// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'approval_args.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApprovalArgs _$ApprovalArgsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ApprovalArgs', json, ($checkedConvert) {
      final val = ApprovalArgs(
        action: $checkedConvert('action', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ApprovalArgsToJson(ApprovalArgs instance) =>
    <String, dynamic>{'action': ?instance.action};
