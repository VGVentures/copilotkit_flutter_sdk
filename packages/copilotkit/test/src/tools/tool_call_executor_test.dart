import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallExecutor, () {
    const executor = ToolCallExecutor();
    final signal = CancellationSignal();

    FrontendTool weatherTool(FrontendToolHandler handler) => FrontendTool(
      name: 'showWeather',
      description: 'Show the weather for a city',
      parameters: Ack.object({
        'city': Ack.string(),
        'days': Ack.integer().optional(),
        'unit': Ack.object({'step': Ack.integer()}).optional(),
        'tags': Ack.list(Ack.string()).optional(),
      }),
      handler: handler,
    );

    ToolCallView callWith(Map<String, Object?> args) => ToolCallView(
      id: 'c1',
      name: 'showWeather',
      status: ToolCallStatus.executing,
      args: args,
    );

    test('runs the handler with the parsed args and the signal', () async {
      Map<String, Object?>? received;
      CancellationSignal? receivedSignal;
      final tool = weatherTool((args, {required signal}) async {
        received = args;
        receivedSignal = signal;
        return 'sunny';
      });

      final outcome = await executor.execute(
        tool,
        callWith({'city': 'Lima', 'days': 3}),
        signal,
      );

      expect(outcome, const ToolCallOutcome(result: 'sunny'));
      expect(received, {'city': 'Lima', 'days': 3});
      expect(receivedSignal, same(signal));
    });

    test('turns a handler error into a generic result and the error', () async {
      final error = StateError('boom');
      final tool = weatherTool((_, {required signal}) => throw error);

      final outcome = await executor.execute(
        tool,
        callWith({'city': 'Lima'}),
        signal,
      );

      expect(outcome.result, FallbackToolResult.handlerError.message);
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, isNotNull);
    });

    group('with invalid args', () {
      var called = false;
      late FrontendTool tool;

      setUp(() {
        called = false;
        tool = weatherTool((_, {required signal}) async {
          called = true;
          return 'ok';
        });
      });

      Future<ToolCallOutcome> outcomeFor(Map<String, Object?> args) =>
          executor.execute(tool, callWith(args), signal);

      test('lists each problem by argument path, without running', () async {
        final outcome = await outcomeFor({'days': '3', 'extra': true});

        expect(
          outcome,
          const ToolCallOutcome(
            result:
                "The tool didn't run: its arguments don't match its "
                'parameters. Fix them and call it again.\n'
                '- city: Required property "city" is missing.\n'
                '- days: Expected integer, got string.\n'
                '- extra: Property "extra" is not allowed.',
          ),
        );
        expect(called, isFalse);
      });

      test('joins nested paths with dots', () async {
        final outcome = await outcomeFor({
          'city': 'Lima',
          'unit': {'step': 'x'},
          'tags': ['a', 1],
        });

        expect(
          outcome.result,
          endsWith(
            '\n- unit.step: Expected integer, got string.'
            '\n- tags.1: Expected string, got integer.',
          ),
        );
      });
    });
  });

  group(ToolCallOutcome, () {
    test('supports value equality', () {
      expect(
        const ToolCallOutcome(result: 'ok'),
        const ToolCallOutcome(result: 'ok'),
      );
      expect(
        const ToolCallOutcome(result: 'ok'),
        isNot(const ToolCallOutcome(result: 'ok', error: 'boom')),
      );
    });
  });
}
