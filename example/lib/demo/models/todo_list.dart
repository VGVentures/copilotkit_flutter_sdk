import 'package:example/demo/models/todo.dart';
import 'package:json_annotation/json_annotation.dart';

part 'todo_list.g.dart';

/// The state the app and the agent share: a todo list.
///
/// Either side edits it. The app sends it with every run, and the agent
/// answers with a state snapshot or delta.
@JsonSerializable()
class const TodoList({final List<Todo> todos = const []}) {
  factory fromJson(Map<String, Object?> json) => _$TodoListFromJson(json);

  Map<String, Object?> toJson() => _$TodoListToJson(this);

  /// Returns this list with a new, open todo [title] at the end.
  TodoList added(String title) => TodoList(
    todos: [
      ...todos,
      Todo(title: title),
    ],
  );

  /// Returns this list with the todo at [index] toggled.
  TodoList toggled(int index) => TodoList(
    todos: [
      for (final (i, todo) in todos.indexed)
        if (i == index) todo.toggled() else todo,
    ],
  );

  /// Returns this list without the todo at [index].
  TodoList removed(int index) => TodoList(
    todos: [
      for (final (i, todo) in todos.indexed)
        if (i != index) todo,
    ],
  );
}
