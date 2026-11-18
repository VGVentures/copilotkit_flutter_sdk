import 'package:ack/ack.dart';
import 'package:copilotkit/src/tools/models/invalid_tool_arguments.dart';
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

      final outcome = await executor(
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

      await executor(
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

      final outcome = await executor(
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

      final outcome = await executor(
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

        final outcome = executor(approval, call, signal, responses: responses);
        responses.respond('c1', 'approved');

        expect(await outcome, const ToolCallOutcome(result: 'approved'));
      });

      test('answers invalid args without waiting', () async {
        final outcome = await executor(
          approval,
          callWith({'city': 'Lima'}),
          signal,
          responses: ToolResponses(),
        );

        expect(outcome.result, contains("arguments don't match"));
      });
    });

    test('returns the invalid arguments without running the tool', () async {
      var called = false;
      final tool = weatherTool((_, {required signal}) async {
        called = true;
        return 'ok';
      });
      const args = {'days': '3'};

      final outcome = await executor(
        tool,
        callWith(args),
        signal,
        responses: ToolResponses(),
      );

      final error = (tool.parameters.safeParse(args) as Fail).error;
      expect(
        outcome,
        ToolCallOutcome(result: InvalidToolArguments(error).message),
      );
      expect(called, isFalse);
    });
  });
}
