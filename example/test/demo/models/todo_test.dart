import 'package:example/demo/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(Todo, () {
    test('decodes and encodes JSON', () {
      final todo = Todo.fromJson(const {'title': 'Buy milk', 'done': true});

      expect(todo.title, 'Buy milk');
      expect(todo.done, isTrue);
      expect(todo.toJson(), {'title': 'Buy milk', 'done': true});
    });

    test('is open when the agent leaves done out', () {
      expect(Todo.fromJson(const {'title': 'Buy milk'}).done, isFalse);
    });

    test('flips done', () {
      final todo = const Todo(title: 'Buy milk').toggled();

      expect(todo.done, isTrue);
      expect(todo.toggled().done, isFalse);
    });
  });
}
