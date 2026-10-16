import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/client_x.dart';

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

  group('context', () {
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
      await client.runAgent(await client.openAgent('default'));
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

    test('sends entries in order with JSON-encoded values', () async {
      client
        ..add(
          ContextAdded(
            AgentContextEntry(
              description: 'Current user',
              value: const {'name': 'Ada'},
            ),
          ),
        )
        ..add(
          ContextAdded(AgentContextEntry(description: 'Locale', value: 'es')),
        )
        ..add(ContextAdded(AgentContextEntry(description: 'Unread', value: 3)));

      final context = await runAndCaptureContext();

      expect(client.state.context.map((e) => e.description), [
        'Current user',
        'Locale',
        'Unread',
      ]);
      expect(context.map((c) => c.description), [
        'Current user',
        'Locale',
        'Unread',
      ]);
      expect(context.map((c) => c.value), ['{"name":"Ada"}', '"es"', '3']);
    });

    test('ContextUpdated sends the new value on the next run', () async {
      final entry = AgentContextEntry(description: 'Unread', value: 3);
      await client.addContext(entry);
      await runAndCaptureContext();

      await client.handled(ContextUpdated(entry.id, 4));

      expect(client.state.context.single.value, 4);
      expect((await runAndCaptureContext()).single.value, '4');
    });

    test('ContextUpdated for an unknown id changes nothing', () async {
      final entry = AgentContextEntry(description: 'Unread', value: 3);
      await client.addContext(entry);

      await client.handled(const ContextUpdated('other', 4));

      expect(client.state.context, [entry]);
    });

    test('ContextRemoved drops the entry from the next run', () async {
      final entry = AgentContextEntry(description: 'Unread', value: 3);
      await client.addContext(entry);
      await client.addContext(
        AgentContextEntry(description: 'Locale', value: 'es'),
      );

      client
        ..add(ContextRemoved(entry.id))
        ..add(ContextRemoved(entry.id));

      final context = await runAndCaptureContext();
      expect(context.map((c) => c.description), ['Locale']);
    });

    test('a value that is not JSON reports an error without running', () async {
      client.add(
        ContextAdded(
          AgentContextEntry(description: 'Clock', value: DateTime(2026)),
        ),
      );

      await client.runAgent(await client.openAgent('default'));

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

  group(AgentContextEntry, () {
    test('generates an id when none is given', () {
      final entry = AgentContextEntry(description: 'Unread', value: 3);

      expect(Uuid.isValidUUID(fromString: entry.id), isTrue);
      expect(entry.description, 'Unread');
      expect(entry.value, 3);
    });

    test('copyWith replaces the value and keeps the id', () {
      final entry = AgentContextEntry(description: 'Unread', value: 3);

      final copy = entry.copyWith(value: 4);

      expect(copy.id, entry.id);
      expect(copy.description, 'Unread');
      expect(copy.value, 4);
    });

    test('supports value equality', () {
      expect(
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
      );
      expect(
        AgentContextEntry(id: 'e1', description: 'Unread', value: 3),
        isNot(AgentContextEntry(id: 'e2', description: 'Unread', value: 3)),
      );
    });
  });
}
