import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgent extends Mock implements CopilotAgent;

class _MockChatRowMapper extends Mock implements ChatRowMapper;

class _MockUuid extends Mock implements Uuid;

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
    late _MockUuid uuid;
    late StreamController<CopilotAgentState> changes;

    setUp(() {
      uuid = _MockUuid();
      when(() => uuid.v4()).thenReturn('m1');
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
        CopilotChatBloc(client: client, agentId: 'default', uuid: uuid);

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

    group('with a mapper', () {
      const rows = [ChatMessageRow(_user)];
      final running = _agentState.copyWith(isRunning: true);
      late _MockChatRowMapper mapper;

      setUp(() {
        mapper = _MockChatRowMapper();
        when(() => mapper.call(_agentState)).thenReturn(const []);
        when(() => mapper.call(running)).thenReturn(rows);
      });

      blocTest<CopilotChatBloc, CopilotChatState>(
        'maps the rows with it',
        build: () =>
            CopilotChatBloc(client: client, agentId: 'default', mapper: mapper),
        act: (bloc) async {
          when(() => agent.state).thenReturn(running);
          bloc.add(const ChatSubscriptionRequested());
          await pumpEventQueue();
          changes.add(_agentState);
        },
        expect: () => [
          const CopilotChatState(rows: rows, isRunning: true),
          const CopilotChatState(),
        ],
        verify: (_) {
          verify(() => mapper.call(_agentState)).called(2);
          verify(() => mapper.call(running)).called(1);
        },
      );
    });

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
      verify: (_) => expect(sentMessages(), [
        const UserMessage(id: 'm1', content: 'Hi there'),
      ]),
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
