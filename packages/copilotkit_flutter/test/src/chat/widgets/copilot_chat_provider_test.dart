import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter/widgets.dart';
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

void main() {
  group(CopilotChatProvider, () {
    late _MockCopilotKitClient client;

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
      when(() => agent.stream).thenAnswer((_) => const Stream.empty());
      return agent;
    }

    setUp(() {
      client = _MockCopilotKitClient();
      stubAgent(client, 'default');
      stubAgent(client, 'other');
    });

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
        isA<ChatMessageRow>().having(
          (row) => row.message.content,
          'content',
          'Hi from default',
        ),
      );
      verify(() => client.agent('default')).called(greaterThan(0));
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
