import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/mock_agent_transport.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('$CopilotKitClient context', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late CopilotKitClient client;

    setUp(() {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      transport.stubRun(() => const Stream.empty());
      client = CopilotKitClient(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
    });

    Future<List<Context>> runAndCaptureContext() async {
      clearInteractions(transport);
      await client.runAgent('default');
      return transport.sentInputs().single.context;
    }

    test('sends entries in order with JSON-encoded values', () async {
      client
        ..addContext(
          AgentContextEntry(
            description: 'Current user',
            value: const {'name': 'Ada'},
          ),
        )
        ..addContext(AgentContextEntry(description: 'Locale', value: 'es'))
        ..addContext(AgentContextEntry(description: 'Unread', value: 3));

      final context = await runAndCaptureContext();

      expect(client.context.map((e) => e.description), [
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

    final entry = AgentContextEntry(description: 'Unread', value: 3);

    test('updateContext sends the new value on the next run', () async {
      client.addContext(entry);
      await runAndCaptureContext();

      client.updateContext(entry.id, 4);

      expect(client.context.single.value, 4);
      final context = await runAndCaptureContext();
      expect(context.single.value, '4');
    });

    test('updateContext for an unknown id changes nothing', () {
      client
        ..addContext(entry)
        ..updateContext('other', 4);

      expect(client.context, [entry]);
    });

    test('removeContext drops the entry from the next run', () async {
      client
        ..addContext(entry)
        ..addContext(AgentContextEntry(description: 'Locale', value: 'es'))
        ..removeContext(entry.id)
        ..removeContext(entry.id);

      final context = await runAndCaptureContext();

      expect(context.map((c) => c.description), ['Locale']);
    });

    test('a value that is not JSON reports an error without running', () async {
      client.addContext(
        AgentContextEntry(description: 'Clock', value: DateTime(2026)),
      );

      await client.runAgent('default');

      expect(errors.single, isA<JsonUnsupportedObjectError>());
      transport.verifyNoRun();
    });
  });
}
