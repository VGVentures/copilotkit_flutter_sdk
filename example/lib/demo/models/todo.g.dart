// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Todo _$TodoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Todo', json, ($checkedConvert) {
      final val = Todo(
        title: $checkedConvert('title', (v) => v as String),
        done: $checkedConvert('done', (v) => v as bool? ?? false),
      );
      return val;
    });

Map<String, dynamic> _$TodoToJson(Todo instance) => <String, dynamic>{
  'title': instance.title,
  'done': instance.done,
};
