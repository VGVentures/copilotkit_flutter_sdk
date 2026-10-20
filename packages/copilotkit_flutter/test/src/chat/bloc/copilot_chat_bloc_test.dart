import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

const _agentState = CopilotAgentState(agentId: 'default', threadId: 't');
const _user = UserMessage(id: 'u1', content: 'Weather in Lima?');
const _call = ToolCallView(
  id: 'c1',
  name: 'showWeather',
  status: ToolCallStatus.executing,
  args: {'city': 'Lima'},
);
const _assistantWithCall = AssistantMessage(
  id: 'a1',
  content: 'Let me check',
  toolCalls: [ToolCall(id: 'c1', name: 'showWeather', arguments: '{}')],
);

void main() {
  group(CopilotChatBloc, () {
    late _MockCopilotKitClient client;
    late _MockCopilotAgent agent;
    late StreamController<CopilotAgentState> changes;

    setUp(() {
      client = _MockCopilotKitClient();
      agent = _MockCopilotAgent();
      when(() => client.agent('default')).thenReturn(agent);
      when(() => client.runAgent(any(), message: any(named: 'message')))
          .thenAnswer((_) async {});
      when(() => client.stopAgent(any())).thenAnswer((_) async {});
      changes = StreamController<CopilotAgentState>.broadcast();
      when(() => agent.state).thenReturn(_agentState);
      when(() => agent.stream).thenAnswer((_) => changes.stream);
    });

    tearDown(() => changes.close());

    CopilotChatBloc buildBloc() =>
        CopilotChatBloc(client: client, agentId: 'default');

    /// The messages the agent was run with so far.
    List<UserMessage> sentMessages() => verify(
      () => client.runAgent('default', message: captureAny(named: 'message')),
    ).captured.cast<UserMessage>();

    blocTest<CopilotChatBloc, CopilotChatState>(
      'starts from the agent state',
      setUp: () => when(() => agent.state).thenReturn(
        _agentState.copyWith(
          messages: [_user],
          isRunning: true,
          error: () => 'boom',
        ),
      ),
      build: buildBloc,
      verify: (bloc) => expect(
        bloc.state,
        const CopilotChatState(
          rows: [ChatMessageRow(_user)],
          isRunning: true,
          error: 'boom',
        ),
      ),
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'maps every agent state to a chat state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const ChatSubscriptionRequested());
        await pumpEventQueue();
        changes
          ..add(_agentState.copyWith(messages: [_user], isRunning: true))
          ..add(
            _agentState.copyWith(
              messages: [_user, _assistantWithCall],
              toolCalls: const [_call],
              isRunning: true,
            ),
          )
          ..add(
            _agentState.copyWith(
              messages: [_user, _assistantWithCall],
              toolCalls: const [_call],
              error: () => 'boom',
            ),
          );
      },
      expect: () => [
        const CopilotChatState(rows: [ChatMessageRow(_user)], isRunning: true),
        const CopilotChatState(
          rows: [
            ChatMessageRow(_user),
            ChatMessageRow(_assistantWithCall),
            ChatToolCallRow(_call),
          ],
          isRunning: true,
        ),
        const CopilotChatState(
          rows: [
            ChatMessageRow(_user),
            ChatMessageRow(_assistantWithCall),
            ChatToolCallRow(_call),
          ],
          error: 'boom',
        ),
      ],
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatSubscriptionRequested catches up with the agent first',
      build: buildBloc,
      act: (bloc) {
        when(() => agent.state)
            .thenReturn(_agentState.copyWith(messages: [_user]));
        bloc.add(const ChatSubscriptionRequested());
      },
      expect: () => [
        const CopilotChatState(rows: [ChatMessageRow(_user)]),
      ],
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'mirrors nothing before ChatSubscriptionRequested',
      build: buildBloc,
      act: (_) => changes.add(_agentState.copyWith(messages: [_user])),
      expect: () => <CopilotChatState>[],
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'stops listening to the agent when closed',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const ChatSubscriptionRequested());
        await pumpEventQueue();
        expect(changes.hasListener, isTrue);
      },
      verify: (_) => expect(changes.hasListener, isFalse),
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent runs the agent with the trimmed user message',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('  Hi there  ')),
      verify: (_) {
        final message = sentMessages().single;
        expect(message.content, 'Hi there');
        expect(Uuid.isValidUUID(fromString: message.id), isTrue);
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent gives each message its own id',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ChatMessageSent('one'))
        ..add(const ChatMessageSent('two')),
      verify: (_) {
        final ids = sentMessages().map((message) => message.id);
        expect(ids.toSet(), hasLength(2));
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent ignores blank text',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('   ')),
      verify: (_) => verifyNever(
        () => client.runAgent(any(), message: any(named: 'message')),
      ),
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatStopRequested stops the agent',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStopRequested()),
      verify: (_) => verify(() => client.stopAgent('default')).called(1),
    );
  });
}
