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

    Future<List<Context>> runAndCaptureContext({
      String agentId = 'default',
    }) async {
      clearInteractions(transport);
      await client.runAgent(await client.openAgent(agentId));
      final input = transport.sentInputs().single;
      return input.context;
    }

    late List<Context> context;
    late List<Context> chatContext;
    late List<Context> defaultContext;

    blocTest<CopilotKitBloc, CopilotKitState>(
      'sends entries in order, encoding every value but strings as JSON',
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
        expect(context.map((c) => c.value), ['{"name":"Ada"}', 'es', '3']);
      },
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'sends a string as it is, even when it holds JSON',
      build: () => client,
      act: (client) async {
        client
          ..add(
            ContextAdded(
              AgentContextEntry(
                description: 'Pre-encoded',
                value: '{"name":"Ada"}',
              ),
            ),
          )
          ..add(
            ContextAdded(AgentContextEntry(description: 'Empty', value: '')),
          )
          ..add(ContextAdded(AgentContextEntry(description: 'Missing')));
        context = await runAndCaptureContext();
      },
      verify: (_) =>
          expect(context.map((c) => c.value), ['{"name":"Ada"}', '', 'null']),
    );

    blocTest<CopilotKitBloc, CopilotKitState>(
      'sends an entry with agent ids only to those agents',
      build: () => client,
      act: (client) async {
        client
          ..add(
            ContextAdded(
              AgentContextEntry(description: 'Everyone', value: 'a'),
            ),
          )
          ..add(
            ContextAdded(
              AgentContextEntry(
                description: 'Ops only',
                value: 'b',
                agentIds: const {'ops'},
              ),
            ),
          )
          ..add(
            ContextAdded(
              AgentContextEntry(
                description: 'Chat and ops',
                value: 'c',
                agentIds: const {'chat', 'ops'},
              ),
            ),
          )
          ..add(
            ContextAdded(
              AgentContextEntry(
                description: 'Nobody',
                value: 'd',
                agentIds: const {},
              ),
            ),
          );
        context = await runAndCaptureContext(agentId: 'ops');
        chatContext = await runAndCaptureContext(agentId: 'chat');
        defaultContext = await runAndCaptureContext();
      },
      verify: (_) {
        expect(context.map((c) => c.description), [
          'Everyone',
          'Ops only',
          'Chat and ops',
        ]);
        expect(chatContext.map((c) => c.description), [
          'Everyone',
          'Chat and ops',
        ]);
        expect(defaultContext.map((c) => c.description), ['Everyone']);
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
