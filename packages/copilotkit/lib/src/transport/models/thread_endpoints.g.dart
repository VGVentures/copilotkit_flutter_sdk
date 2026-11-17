// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_endpoints.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreadEndpoints _$ThreadEndpointsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ThreadEndpoints', json, ($checkedConvert) {
      final val = ThreadEndpoints(
        list: $checkedConvert('list', (v) => v as bool? ?? false),
        inspect: $checkedConvert('inspect', (v) => v as bool? ?? false),
        mutations: $checkedConvert('mutations', (v) => v as bool? ?? false),
        realtimeMetadata: $checkedConvert(
          'realtimeMetadata',
          (v) => v as bool? ?? false,
        ),
      );
      return val;
    });
