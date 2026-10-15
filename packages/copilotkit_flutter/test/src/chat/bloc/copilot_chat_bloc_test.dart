import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class _MockCopilotAgent extends Mock implements CopilotAgent;

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
  setUpAll(() => registerFallbackValue(UserMessage(id: 'x', content: 'x')));

  group(CopilotChatBloc, () {
    late _MockCopilotAgent agent;
    late StreamController<AgentSnapshot> changes;

    setUp(() {
      agent = _MockCopilotAgent();
      changes = StreamController<AgentSnapshot>.broadcast();
      when(() => agent.snapshot).thenReturn(const AgentSnapshot());
      when(() => agent.changes).thenAnswer((_) => changes.stream);
      when(() => agent.isRunning).thenReturn(false);
      when(() => agent.addMessage(any())).thenAnswer((_) async {});
      when(() => agent.run()).thenAnswer((_) async {});
      when(() => agent.stop()).thenAnswer((_) async {});
    });

    tearDown(() => changes.close());

    test('starts from the agent snapshot', () {
      when(() => agent.snapshot).thenReturn(
        AgentSnapshot(messages: [_user], isRunning: true, error: 'boom'),
      );

      final bloc = CopilotChatBloc(agent: agent);
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
      'maps every agent snapshot to a chat state',
      build: () => CopilotChatBloc(agent: agent),
      act: (_) {
        changes
          ..add(AgentSnapshot(messages: [_user], isRunning: true))
          ..add(
            AgentSnapshot(
              messages: [_user, _assistantWithCall],
              toolCalls: const [_call],
              isRunning: true,
            ),
          )
          ..add(
            AgentSnapshot(
              messages: [_user, _assistantWithCall],
              toolCalls: const [_call],
              error: 'boom',
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

    group('rows', () {
      test('hide tool, system and empty messages', () {
        final rows = CopilotChatState.fromSnapshot(
          AgentSnapshot(
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

        final rows = CopilotChatState.fromSnapshot(
          const AgentSnapshot(messages: [callOnly], toolCalls: [_call]),
        ).rows;

        expect(rows, [const ChatToolCallRow(_call)]);
      });
    });

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent adds the trimmed user message and runs the agent',
      build: () => CopilotChatBloc(agent: agent),
      act: (bloc) => bloc.add(const ChatMessageSent('  Hi there  ')),
      verify: (_) {
        final message =
            verify(() => agent.addMessage(captureAny())).captured.single
                as UserMessage;
        expect(message.content, 'Hi there');
        expect(message.id, isNotEmpty);
        verify(() => agent.run()).called(1);
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent gives each message its own id',
      build: () => CopilotChatBloc(agent: agent),
      act: (bloc) => bloc
        ..add(const ChatMessageSent('one'))
        ..add(const ChatMessageSent('two')),
      verify: (_) {
        final ids = verify(() => agent.addMessage(captureAny())).captured
            .cast<UserMessage>()
            .map((m) => m.id);
        expect(ids.toSet(), hasLength(2));
        expect(ids.every((id) => Uuid.isValidUUID(fromString: id!)), isTrue);
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent ignores blank text',
      build: () => CopilotChatBloc(agent: agent),
      act: (bloc) => bloc.add(const ChatMessageSent('   ')),
      verify: (_) {
        verifyNever(() => agent.addMessage(any()));
        verifyNever(() => agent.run());
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatMessageSent is ignored while the agent runs',
      setUp: () => when(() => agent.isRunning).thenReturn(true),
      build: () => CopilotChatBloc(agent: agent),
      act: (bloc) => bloc.add(const ChatMessageSent('Hi')),
      verify: (_) {
        verifyNever(() => agent.addMessage(any()));
        verifyNever(() => agent.run());
      },
    );

    blocTest<CopilotChatBloc, CopilotChatState>(
      'ChatStopRequested stops the agent',
      build: () => CopilotChatBloc(agent: agent),
      act: (bloc) => bloc.add(const ChatStopRequested()),
      verify: (_) => verify(() => agent.stop()).called(1),
    );

    test('close stops listening to the agent', () async {
      final bloc = CopilotChatBloc(agent: agent);
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
    });
  });
}
