import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallExecutor, () {
    const executor = ToolCallExecutor();
    final signal = CancellationSignal();

    FrontendTool<Map<String, Object?>> weatherTool(
      FrontendToolHandler<Map<String, Object?>> handler,
    ) => FrontendTool(
      name: 'showWeather',
      description: 'Show the weather for a city',
      parameters: Ack.object({
        'city': Ack.string(),
        'days': Ack.integer().optional(),
        'unit': Ack.object({'step': Ack.integer()}).optional(),
        'tags': Ack.list(Ack.string()).optional(),
      }),
      decode: Map<String, Object?>.of,
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
        responses: ToolResponses(),
      );

      expect(outcome, const ToolCallOutcome(result: 'sunny'));
      expect(received, const {'city': 'Lima', 'days': 3});
      expect(receivedSignal, same(signal));
    });

    test('decodes unmodifiable args', () async {
      Map<String, Object?>? decoded;
      final tool = FrontendTool<Map<String, Object?>>(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: Ack.object({'city': Ack.string()}),
        decode: (json) => decoded = json,
        handler: (_, {required signal}) async => 'sunny',
      );

      await executor.execute(
        tool,
        callWith({'city': 'Lima'}),
        signal,
        responses: ToolResponses(),
      );

      expect(() => decoded!['city'] = 'Quito', throwsUnsupportedError);
    });

    test('turns a handler error into a generic result and the error', () async {
      final error = StateError('boom');
      final tool = weatherTool((_, {required signal}) => throw error);

      final outcome = await executor.execute(
        tool,
        callWith({'city': 'Lima'}),
        signal,
        responses: ToolResponses(),
      );

      expect(outcome.result, FallbackToolResult.handlerError.message);
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, isNotNull);
    });

    test('turns a decoder error into a generic result and the error', () async {
      final tool = FrontendTool<String>(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: Ack.object({'city': Ack.string()}),
        decode: (json) => throw const FormatException('bad args'),
        handler: (_, {required signal}) async => 'never',
      );

      final outcome = await executor.execute(
        tool,
        callWith({'city': 'Lima'}),
        signal,
        responses: ToolResponses(),
      );

      expect(outcome.result, FallbackToolResult.handlerError.message);
      expect(outcome.error, isA<FormatException>());
    });

    group('for a human-in-the-loop tool', () {
      final approval = HumanInTheLoopTool(
        name: 'confirmAction',
        description: 'Ask the user to confirm an action',
        parameters: Ack.object({'action': Ack.string()}),
        decode: Map<String, Object?>.of,
      );
      const call = ToolCallView(
        id: 'c1',
        name: 'confirmAction',
        status: ToolCallStatus.executing,
        args: {'action': 'delete'},
      );

      test('waits for the answer', () async {
        final responses = ToolResponses();

        final outcome = executor.execute(
          approval,
          call,
          signal,
          responses: responses,
        );
        responses.respond('c1', 'approved');

        expect(await outcome, const ToolCallOutcome(result: 'approved'));
      });

      test('answers invalid args without waiting', () async {
        final outcome = await executor.execute(
          approval,
          callWith({'city': 'Lima'}),
          signal,
          responses: ToolResponses(),
        );

        expect(outcome.result, contains("arguments don't match"));
      });
    });

    group('accepts', () {
      final tool = weatherTool((_, {required signal}) async => 'ok');

      test('is true when the args match the parameters', () {
        expect(executor.accepts(tool, callWith({'city': 'Lima'})), isTrue);
      });

      test('is false when they do not', () {
        expect(executor.accepts(tool, callWith({'days': 3})), isFalse);
      });
    });

    group('with invalid args', () {
      var called = false;
      late FrontendTool<Map<String, Object?>> tool;

      setUp(() {
        called = false;
        tool = weatherTool((_, {required signal}) async {
          called = true;
          return 'ok';
        });
      });

      Future<ToolCallOutcome> outcomeFor(Map<String, Object?> args) => executor
          .execute(tool, callWith(args), signal, responses: ToolResponses());

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
