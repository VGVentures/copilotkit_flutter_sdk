import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit/copilotkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_agent_transport.dart';
import '../../../helpers/test_copilot_kit_bloc.dart';

void main() {
  setUpAll(MockAgentTransport.registerFallbacks);

  group('context', () {
    late MockAgentTransport transport;
    late List<Object> errors;
    late TestCopilotKitBloc client;

    setUp(() {
      transport = MockAgentTransport();
      when(() => transport.close()).thenAnswer((_) async {});
      errors = [];
      transport.stubRun(() => const Stream.empty());
      client = TestCopilotKitBloc(
        runtimeUrl: Uri.parse('http://runtime.test/api/copilotkit'),
        onError: (error, _) => errors.add(error),
        transport: transport,
      );
    });

    Future<List<Context>> runAndCaptureContext() async {
      clearInteractions(transport);
      await client.runAgent(await client.openAgent('default'));
      final input = transport.sentInputs().single;
      return input.context;
    }

    late List<Context> context;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'sends entries in order with JSON-encoded values',
      build: () => client,
      act: (client) async {
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
          ..add(
            ContextAdded(AgentContextEntry(description: 'Unread', value: 3)),
          );
        context = await runAndCaptureContext();
      },
      verify: (client) {
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
      },
    );

    final entry = AgentContextEntry(description: 'Unread', value: 3);

    blocTest<CopilotKitBloc, CopilotKitState>(
      'ContextUpdated sends the new value on the next run',
      setUp: () async {
        await client.addContext(entry);
        await runAndCaptureContext();
      },
      build: () => client,
      act: (_) async {
        await client.handled(ContextUpdated(entry.id, 4));
        expect(client.state.context.single.value, 4);
        context = await runAndCaptureContext();
      },
      verify: (_) => expect(context.single.value, '4'),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'ContextUpdated for an unknown id changes nothing',
      setUp: () => client.addContext(entry),
      build: () => client,
      act: (client) => client.add(const ContextUpdated('other', 4)),
      expect: () => const <CopilotKitState>[],
      verify: (client) => expect(client.state.context, [entry]),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'ContextRemoved drops the entry from the next run',
      setUp: () async {
        await client.addContext(entry);
        await client.addContext(
          AgentContextEntry(description: 'Locale', value: 'es'),
        );
      },
      build: () => client,
      act: (client) async {
        client
          ..add(ContextRemoved(entry.id))
          ..add(ContextRemoved(entry.id));
        context = await runAndCaptureContext();
      },
      verify: (_) => expect(context.map((c) => c.description), ['Locale']),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'a value that is not JSON reports an error without running',
      build: () => client,
      act: (_) async {
        client.add(
          ContextAdded(
            AgentContextEntry(description: 'Clock', value: DateTime(2026)),
          ),
        );
        await client.runAgent(await client.openAgent('default'));
      },
      verify: (_) {
        expect(errors.single, isA<JsonUnsupportedObjectError>());
        transport.verifyNoRun();
      },
    );
  });
}
