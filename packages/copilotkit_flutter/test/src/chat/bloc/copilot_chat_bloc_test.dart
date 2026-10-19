import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _MockCopilotKitClient extends Mock implements CopilotKitClient;

class _MockCopilotAgentBloc extends Mock implements CopilotAgentBloc;

const _agentState = CopilotAgentState(agentId: 'default', threadId: 't');

final _user = UserMessage(id: 'u1', content: 'Weather in Lima?');
const _assistant = AssistantMessage(id: 'a1', content: 'Let me check');
const _call = ToolCallView(
  id: 'c1',
  name: 'showWeather',
  status: ToolCallStatus.executing,
  args: {'city': 'Lima'},
);
const _assistantWithCall = AssistantMessage(
  id: 'a1',
  content: 'Let me check',
  toolCalls: [
    ToolCall(
      id: 'c1',
      function: FunctionCall(name: 'showWeather', arguments: '{}'),
    ),
  ],
);

void main() {
  setUpAll(() => registerFallbackValue(const AgentOpened('fallback')));

  group(CopilotChatBloc, () {
    late _MockCopilotKitClient client;
    late _MockCopilotAgentBloc agent;
    late StreamController<CopilotAgentState> changes;

    setUp(() {
      client = _MockCopilotKitClient();
      agent = _MockCopilotAgentBloc();
      changes = StreamController<CopilotAgentState>.broadcast();
      when(() => agent.state).thenReturn(_agentState);
      when(() => agent.stream).thenAnswer((_) => changes.stream);
    });

    tearDown(() => changes.close());

    CopilotChatBloc buildBloc() =>
        CopilotChatBloc(client: client, agent: agent);

    /// The events added to the client so far.
    List<CopilotKitEvent> clientEvents() =>
        verify(() => client.add(captureAny())).captured.cast<CopilotKitEvent>();

    test('starts from the agent state', () {
      when(() => agent.state).thenReturn(
        _agentState.copyWith(
          messages: [_user],
          isRunning: true,
          error: () => 'boom',
        ),
      );

      final bloc = buildBloc();
      addTearDown(bloc.close);

      expect(
        bloc.state,
        CopilotChatState(
          rows: [ChatMessageRow(_user)],
          isRunning: true,
          error: 'boom',
        ),
      );
    });

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
        CopilotChatState(rows: [ChatMessageRow(_user)], isRunning: true),
        CopilotChatState(
          rows: [
            ChatMessageRow(_user),
            const ChatMessageRow(_assistantWithCall),
            const ChatToolCallRow(_call),
          ],
          isRunning: true,
        ),
        CopilotChatState(
          rows: [
            ChatMessageRow(_user),
            const ChatMessageRow(_assistantWithCall),
            const ChatToolCallRow(_call),
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
        CopilotChatState(rows: [ChatMessageRow(_user)]),
      ],
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'mirrors nothing before ChatSubscriptionRequested',
      build: buildBloc,
      act: (_) => changes.add(_agentState.copyWith(messages: [_user])),
      expect: () => <CopilotChatState>[],
    );

    group('rows', () {
      test('hide tool, system and empty messages', () {
        final rows = CopilotChatState.fromAgentState(
          _agentState.copyWith(
            messages: [
              const SystemMessage(id: 's', content: 'Be nice'),
              _user,
              const AssistantMessage(id: 'empty', content: ''),
              const AssistantMessage(id: 'none'),
              const ToolMessage(id: 't', content: 'ok', toolCallId: 'c'),
              UserMessage(id: 'blank', content: ''),
              _assistant,
            ],
          ),
        ).rows;

        expect(rows, [ChatMessageRow(_user), const ChatMessageRow(_assistant)]);
      });

      test('show tool calls after their message, even without text', () {
        const callOnly = AssistantMessage(
          id: 'a2',
          toolCalls: [
            ToolCall(
              id: 'c1',
              function: FunctionCall(name: 'showWeather', arguments: '{}'),
            ),
            ToolCall(
              id: 'unknown',
              function: FunctionCall(name: 'other', arguments: '{}'),
            ),
          ],
        );

        final rows = CopilotChatState.fromAgentState(
          _agentState.copyWith(messages: [callOnly], toolCalls: [_call]),
        ).rows;

        expect(rows, [const ChatToolCallRow(_call)]);
      });
    });

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent runs the agent with the trimmed user message',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('  Hi there  ')),
      verify: (_) {
        final event = clientEvents().single as AgentRunRequested;
        expect(event.agentId, 'default');
        final message = event.message! as UserMessage;
        expect(message.content, 'Hi there');
        expect(Uuid.isValidUUID(fromString: message.id!), isTrue);
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent gives each message its own id',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ChatMessageSent('one'))
        ..add(const ChatMessageSent('two')),
      verify: (_) {
        final ids = clientEvents().cast<AgentRunRequested>().map(
          (event) => event.message!.id,
        );
        expect(ids.toSet(), hasLength(2));
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent ignores blank text',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatMessageSent('   ')),
      verify: (_) => verifyNever(() => client.add(any())),
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatStopRequested stops the agent',
      build: buildBloc,
      act: (bloc) => bloc.add(const ChatStopRequested()),
      verify: (_) =>
          verify(() => client.add(const AgentStopRequested('default')))
              .called(1),
    );

    test('close stops listening to the agent', () async {
      final bloc = buildBloc()..add(const ChatSubscriptionRequested());
      await pumpEventQueue();
      expect(changes.hasListener, isTrue);

      await bloc.close();

      expect(changes.hasListener, isFalse);
    });

    test('events support value equality', () {
      // Non-const instances, so equality goes through props.
      // ignore_for_file: prefer_const_constructors
      expect(ChatMessageSent('a'), ChatMessageSent('a'));
      expect(ChatMessageSent('a'), isNot(ChatMessageSent('b')));
      expect(ChatStopRequested(), ChatStopRequested());
      expect(ChatSubscriptionRequested(), ChatSubscriptionRequested());
    });
  });
}
