// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoList _$TodoListFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TodoList', json, ($checkedConvert) {
      final val = TodoList(
        todos: $checkedConvert(
          'todos',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => Todo.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
        ),
      );
      return val;
    });

Map<String, dynamic> _$TodoListToJson(TodoList instance) => <String, dynamic>{
  'todos': instance.todos.map((e) => e.toJson()).toList(),
};
