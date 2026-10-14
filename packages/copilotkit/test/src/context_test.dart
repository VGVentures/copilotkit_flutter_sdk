import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAgentTransport extends Mock implements AgentTransport;

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        tools: [],
        context: [],
      ),
    );
  });

  group('addContext', () {
    late _MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;

    setUp(() {
      transport = _MockAgentTransport();
      errors = [];
      when(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) => const Stream.empty());
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
    });

    Future<List<Context>> runAndCaptureContext() async {
      clearInteractions(transport);
      await client.agent('default').run();
      final input =
          verify(
                () => transport.run(
                  agentId: any(named: 'agentId'),
                  input: captureAny(named: 'input'),
                  headers: any(named: 'headers'),
                ),
              ).captured.single
              as RunAgentInput;
      return input.context;
    }

    test('returns an entry with the description and value', () {
      final entry = client.addContext('Current user', {'name': 'Ada'});

      expect(entry.description, 'Current user');
      expect(entry.value, {'name': 'Ada'});
    });

    test('sends live entries in order with JSON-encoded values', () async {
      client
        ..addContext('Current user', {'name': 'Ada'})
        ..addContext('Locale', 'es')
        ..addContext('Unread', 3);

      final context = await runAndCaptureContext();

      expect(context.map((c) => c.description), [
        'Current user',
        'Locale',
        'Unread',
      ]);
      expect(context.map((c) => c.value), ['{"name":"Ada"}', '"es"', '3']);
    });

    test('update sends the new value on the next run', () async {
      final entry = client.addContext('Unread', 3);
      await runAndCaptureContext();

      entry.update(4);

      expect(entry.value, 4);
      expect((await runAndCaptureContext()).single.value, '4');
    });

    test('remove drops the entry from the next run', () async {
      final entry = client.addContext('Unread', 3);
      client.addContext('Locale', 'es');

      entry
        ..remove()
        ..remove();

      final context = await runAndCaptureContext();
      expect(context.map((c) => c.description), ['Locale']);
    });

    test('a value that is not JSON reports an error without running', () async {
      client.addContext('Clock', DateTime(2026));

      await client.agent('default').run();

      expect(errors.single, isA<JsonUnsupportedObjectError>());
      verifyNever(
        () => transport.run(
          agentId: any(named: 'agentId'),
          input: any(named: 'input'),
          headers: any(named: 'headers'),
        ),
      );
    });
  });
}
