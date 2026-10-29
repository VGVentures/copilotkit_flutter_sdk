import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/models/invalid_tool_arguments.dart';
import 'package:test/test.dart';

void main() {
  group(InvalidToolArguments, () {
    final parameters = Ack.object({
      'city': Ack.string(),
      'days': Ack.integer().optional(),
      'unit': Ack.object({'step': Ack.integer()}).optional(),
      'tags': Ack.list(Ack.string()).optional(),
    });

    InvalidToolArguments invalid(Map<String, Object?> args) =>
        switch (parameters.safeParse(args)) {
          Fail(:final error) => InvalidToolArguments(error),
          Ok() => throw StateError('$args are valid'),
        };

    test('lists the innermost problems', () {
      expect(
        invalid({'days': '3', 'extra': true}).problems.map((e) => e.path),
        unorderedEquals(['#/city', '#/days', '#/extra']),
      );
    });

    test('a single problem is its own innermost problem', () {
      final error = SchemaConstraintsError(
        constraints: const [],
        context: SchemaContext(name: 'city', schema: Ack.string(), value: 1),
      );

      expect(InvalidToolArguments(error).problems, [error]);
    });

    test('describes each problem by argument path', () {
      expect(
        invalid({'days': '3', 'extra': true}).message,
        "The tool didn't run: its arguments don't match its parameters. "
        'Fix them and call it again.\n'
        '- city: Required property "city" is missing.\n'
        '- days: Expected integer, got string.\n'
        '- extra: Property "extra" is not allowed.',
      );
    });

    test('joins nested paths with dots', () {
      expect(
        invalid({
          'city': 'Lima',
          'unit': {'step': 'x'},
          'tags': ['a', 1],
        }).message,
        endsWith(
          '\n- unit.step: Expected integer, got string.'
          '\n- tags.1: Expected string, got integer.',
        ),
      );
    });

    test('supports value equality by message', () {
      expect(invalid({'days': '3'}), invalid({'days': '3'}));
      expect(invalid({'days': '3'}), isNot(invalid({'city': 1})));
    });
  });
}
