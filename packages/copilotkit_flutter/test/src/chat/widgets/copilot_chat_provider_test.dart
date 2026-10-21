import 'dart:async';

import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

/// Records the chat bloc it finds on every build.
class const _BlocProbe(final void Function(CopilotChatBloc bloc) onBuild)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    onBuild(context.read<CopilotChatBloc>());
    return const SizedBox();
  }
}

/// A child with state of its own: how many times it was tapped.
class const _Counter() extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _taps++),
      child: Text('taps $_taps'),
    );
  }
}

void main() {
  group(CopilotChatProvider, () {
    late _MockCopilotKitClient client;
    late StreamController<CopilotAgentState> changes;

    _MockCopilotAgent stubAgent(_MockCopilotKitClient client, String id) {
      final agent = _MockCopilotAgent();
      when(() => client.agent(id)).thenReturn(agent);
      when(() => agent.state).thenReturn(
        CopilotAgentState(
          agentId: id,
          threadId: 't',
          messages: [UserMessage(id: 'u1', content: 'Hi from $id')],
        ),
      );
      when(() => agent.stream).thenAnswer((_) => changes.stream);
      return agent;
    }

    setUp(() {
      changes = StreamController<CopilotAgentState>.broadcast();
      client = _MockCopilotKitClient();
      stubAgent(client, 'default');
      stubAgent(client, 'other');
    });

    tearDown(() => changes.close());

    Widget build({
      required CopilotKitClient client,
      required String agentId,
      required void Function(CopilotChatBloc bloc) onBuild,
    }) => CopilotKit.value(
      client: client,
      child: CopilotChatProvider(agentId: agentId, child: _BlocProbe(onBuild)),
    );

    testWidgets('provides a chat bloc for the agent', (tester) async {
      late CopilotChatBloc bloc;

      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: (b) => bloc = b),
      );

      expect(
        bloc.state.rows.single,
        const ChatMessageRow(UserMessage(id: 'u1', content: 'Hi from default')),
      );
      verify(() => client.agent('default')).called(greaterThan(0));
    });

    testWidgets('subscribes the bloc to the agent', (tester) async {
      late CopilotChatBloc bloc;
      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: (b) => bloc = b),
      );

      changes.add(const CopilotAgentState(agentId: 'default', threadId: 't'));
      await tester.pump();

      expect(bloc.state.rows, isEmpty);
    });

    testWidgets('keeps the bloc across rebuilds', (tester) async {
      final blocs = <CopilotChatBloc>[];

      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: blocs.add),
      );
      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: blocs.add),
      );

      expect(blocs, hasLength(2));
      expect(blocs.last, same(blocs.first));
    });

    testWidgets('creates a new bloc when the agent changes', (tester) async {
      final blocs = <CopilotChatBloc>[];

      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: blocs.add),
      );
      await tester.pumpWidget(
        build(client: client, agentId: 'other', onBuild: blocs.add),
      );

      expect(blocs.last, isNot(same(blocs.first)));
      expect(blocs.first.isClosed, isTrue);
    });

    testWidgets('keeps the state of its child when the agent changes', (
      tester,
    ) async {
      Widget build(String agentId) => CopilotKit.value(
        client: client,
        child: MaterialApp(
          home: CopilotChatProvider(agentId: agentId, child: const _Counter()),
        ),
      );
      await tester.pumpWidget(build('default'));
      await tester.tap(find.byType(TextButton));
      await tester.pump();

      await tester.pumpWidget(build('other'));

      expect(find.text('taps 1'), findsOneWidget);
    });

    testWidgets('opens no agent on the old client when both change', (
      tester,
    ) async {
      final other = _MockCopilotKitClient();
      stubAgent(other, 'other');
      final blocs = <CopilotChatBloc>[];

      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: blocs.add),
      );
      clearInteractions(client);
      await tester.pumpWidget(
        build(client: other, agentId: 'other', onBuild: blocs.add),
      );

      verifyNever(() => client.agent(any()));
      verify(() => other.agent('other')).called(greaterThan(0));
      expect(blocs.first.isClosed, isTrue);
    });

    testWidgets('closes the bloc when removed', (tester) async {
      late CopilotChatBloc bloc;
      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: (b) => bloc = b),
      );

      await tester.pumpWidget(const SizedBox());

      expect(bloc.isClosed, isTrue);
    });

    testWidgets('creates a new bloc when the client changes', (tester) async {
      final other = _MockCopilotKitClient();
      stubAgent(other, 'default');
      final blocs = <CopilotChatBloc>[];

      await tester.pumpWidget(
        build(client: client, agentId: 'default', onBuild: blocs.add),
      );
      await tester.pumpWidget(
        build(client: other, agentId: 'default', onBuild: blocs.add),
      );

      expect(blocs.last, isNot(same(blocs.first)));
      verify(() => other.agent('default')).called(greaterThan(0));
    });
  });
}
