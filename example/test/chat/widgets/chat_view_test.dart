import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:example/chat/widgets/chat_view.dart';
import 'package:example/chat/widgets/composer.dart';
import 'package:example/chat/widgets/message_list.dart';
import 'package:example/memories/widgets/memories_view.dart';
import 'package:example/threads/widgets/threads_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements CopilotKitClient;

class _MockThreadsClient extends Mock implements ThreadsClient;

class _MockMemoriesClient extends Mock implements MemoriesClient;

class _MockCopilotChatBloc extends MockBloc<CopilotChatEvent, CopilotChatState>
    implements CopilotChatBloc;

void main() {
  group(ChatView, () {
    late _MockCopilotChatBloc bloc;

    setUp(() => bloc = _MockCopilotChatBloc());

    Future<void> pump(WidgetTester tester, {Widget? header}) {
      return tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<CopilotChatBloc>.value(
            value: bloc,
            child: ChatView(header: header),
          ),
        ),
      );
    }

    testWidgets('shows the message list and the composer', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState());

      await pump(tester);

      expect(find.byType(MessageList), findsOneWidget);
      expect(find.byType(Composer), findsOneWidget);
      expect(find.byKey(const Key('chat_error')), findsNothing);
    });

    testWidgets('shows the header above the message list', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState());

      await pump(tester, header: const Text('Header'));

      expect(find.text('Header'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Header')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(MessageList)).dy),
      );
    });

    testWidgets('shows a notice when the last run failed', (tester) async {
      when(() => bloc.state).thenReturn(const CopilotChatState(error: 'boom'));

      await pump(tester);

      expect(find.byKey(const Key('chat_error')), findsOneWidget);
    });

    group('conversations', () {
      late _MockClient client;
      late String agentThreadId;

      setUp(() {
        client = _MockClient();
        final threads = _MockThreadsClient();
        final real = CopilotKitClient(runtimeUrl: Uri.parse('http://x/api'));
        addTearDown(real.close);
        // The agent the scope opens. Opened without a thread, so it connects
        // to nothing.
        final agent = real.agent('default');
        agentThreadId = agent.state.threadId;
        when(() => client.agent('default', threadId: any(named: 'threadId')))
            .thenReturn(agent);
        when(client.threadEndpoints)
            .thenAnswer((_) async => const ThreadEndpoints(list: true));
        when(() => client.threads).thenReturn(threads);
        when(
          () => threads.list(
            agentId: any(named: 'agentId'),
            includeArchived: any(named: 'includeArchived'),
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
          ),
        ).thenAnswer(
          (_) async => ThreadPage(
            threads: [
              ThreadRecord(
                id: 'thread-2',
                agentId: 'default',
                archived: false,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                name: 'Trip',
              ),
            ],
          ),
        );
        when(() => client.switchAgentThread(any(), any()))
            .thenAnswer((_) async {});
        when(() => bloc.state).thenReturn(const CopilotChatState());
      });

      Future<void> pumpWith(
        WidgetTester tester, {
        ValueChanged<String>? onThreadSelected,
      }) => tester.pumpWidget(
        MaterialApp(
          home: CopilotKit.value(
            client: client,
            child: CopilotAgentScope(
              agentId: 'default',
              threadId: 'thread-1',
              child: BlocProvider<CopilotChatBloc>.value(
                value: bloc,
                child: ChatView(onThreadSelected: onThreadSelected),
              ),
            ),
          ),
        ),
      );

      testWidgets('switches the agent to the thread that is picked', (
        tester,
      ) async {
        final selected = <String>[];
        await pumpWith(tester, onThreadSelected: selected.add);

        await tester.tap(find.byKey(const Key('open_threads')));
        await tester.pumpAndSettle();
        expect(find.byType(ThreadsView), findsOneWidget);
        expect(
          tester.widget<ThreadsView>(find.byType(ThreadsView)).currentThreadId,
          agentThreadId,
        );
        await tester.tap(find.byKey(const Key('thread_thread-2')));
        await tester.pumpAndSettle();

        verify(() => client.switchAgentThread('default', 'thread-2')).called(1);
        expect(selected, ['thread-2']);
      });

      testWidgets('opens the memories', (tester) async {
        final memories = _MockMemoriesClient();
        when(() => client.memories).thenReturn(memories);
        when(() => memories.watch(onConnected: any(named: 'onConnected')))
            .thenAnswer((_) => const Stream.empty());
        when(
          () => memories.list(
            includeInvalidated: any(named: 'includeInvalidated'),
          ),
        ).thenAnswer((_) async => const []);
        await pumpWith(tester);

        await tester.tap(find.byKey(const Key('open_memories')));
        await tester.pumpAndSettle();

        expect(find.byType(MemoriesView), findsOneWidget);
      });

      testWidgets('stays on the thread when the list is left', (tester) async {
        await pumpWith(tester);

        await tester.tap(find.byKey(const Key('open_threads')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        verifyNever(() => client.switchAgentThread(any(), any()));
      });

      testWidgets('switches without a callback to tell', (tester) async {
        await pumpWith(tester);

        await tester.tap(find.byKey(const Key('open_threads')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('new_thread')));
        await tester.pumpAndSettle();

        verify(() => client.switchAgentThread('default', any())).called(1);
      });
    });
  });
}
