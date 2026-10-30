import 'package:example/demo/models/todo.dart';
import 'package:example/demo/models/todo_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(TodoList, () {
    const list = TodoList(
      todos: [
        Todo(title: 'Buy milk'),
        Todo(title: 'Call Ada', done: true),
      ],
    );

    test('decodes and encodes JSON', () {
      const json = {
        'todos': [
          {'title': 'Buy milk', 'done': false},
          {'title': 'Call Ada', 'done': true},
        ],
      };

      expect(TodoList.fromJson(json).toJson(), json);
    });

    group('fromShared', () {
      test('decodes the list in the shared state', () {
        expect(TodoList.fromShared(list.toJson()).toJson(), list.toJson());
      });

      test('is empty without shared state', () {
        expect(TodoList.fromShared(null).todos, isEmpty);
      });

      test('is empty when the shared state is not a todo list', () {
        expect(TodoList.fromShared(const {'todos': 'nope'}).todos, isEmpty);
      });
    });

    test('is empty when the state has no todos', () {
      expect(TodoList.fromJson(const {}).todos, isEmpty);
    });

    test('adds an open todo at the end', () {
      final added = list.added('Pay rent');

      expect(added.todos.map((todo) => todo.title), [
        'Buy milk',
        'Call Ada',
        'Pay rent',
      ]);
      expect(added.todos.last.done, isFalse);
    });

    test('toggles only the todo at the index', () {
      final toggled = list.toggled(0);

      expect(toggled.todos.map((todo) => todo.done), [true, true]);
      expect(list.toggled(1).todos.map((todo) => todo.done), [false, false]);
    });

    test('removes the todo at the index', () {
      expect(list.removed(0).todos.map((todo) => todo.title), ['Call Ada']);
    });
  });
}
