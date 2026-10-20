import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/agent/mappers/text_message_mapper.dart';
import 'package:test/test.dart';

import '../../../helpers/agent.dart';

void main() {
  group(TextMessageMapper, () {
    const mapper = TextMessageMapper();
    const state = AgentFixtures.state;
    final user = UserMessage(id: 'u1', content: 'Hi');

    group('start', () {
      test('appends an empty message from the role', () {
        final next = mapper.start(
          state.copyWith(messages: [user]),
          'm1',
          TextMessageRole.assistant,
          null,
        );

        expect(next.messages, [
          user,
          isA<AssistantMessage>()
              .having((m) => m.id, 'id', 'm1')
              .having((m) => m.content, 'content', ''),
        ]);
      });

      test('keeps the name of the message', () {
        final next = mapper.start(
          state,
          'm1',
          TextMessageRole.assistant,
          'helper',
        );

        expect(next.messages.single.name, 'helper');
      });

      test('creates a message of each role', () {
        final kinds = {
          TextMessageRole.assistant: isA<AssistantMessage>(),
          TextMessageRole.user: isA<UserMessage>(),
          TextMessageRole.system: isA<SystemMessage>(),
          TextMessageRole.developer: isA<DeveloperMessage>(),
        };

        for (final MapEntry(key: role, value: kind) in kinds.entries) {
          final next = mapper.start(state, role.name, role, null);

          expect(next.messages.single, kind, reason: role.name);
        }
      });
    });

    group('append', () {
      final started = state.copyWith(
        messages: [const AssistantMessage(id: 'm1', content: 'Hel')],
      );

      test('appends the delta to the message', () {
        final next = mapper.append(
          started,
          'm1',
          TextMessageRole.assistant,
          'lo',
        );

        expect(next.messages.single.content, 'Hello');
      });

      test('does not mutate the given state', () {
        mapper.append(started, 'm1', TextMessageRole.assistant, 'lo');

        expect(started.messages.single.content, 'Hel');
      });

      test('appends to the message with the id', () {
        final next = mapper.append(
          started.copyWith(
            messages: [
              ...started.messages,
              const AssistantMessage(id: 'm2', content: 'Second'),
            ],
          ),
          'm1',
          TextMessageRole.assistant,
          '!',
        );

        expect(next.messages.map((m) => m.content), ['Hel!', 'Second']);
      });

      test('creates a message from the role when there is none', () {
        final next = mapper.append(state, 'u2', TextMessageRole.user, 'Hey');

        expect(
          next.messages.single,
          isA<UserMessage>()
              .having((m) => m.id, 'id', 'u2')
              .having((m) => m.content, 'content', 'Hey'),
        );
      });

      test('keeps the kind and name of each text message', () {
        final next = mapper.append(
          mapper.append(
            mapper.append(
              state.copyWith(
                messages: [
                  UserMessage(id: 'u', content: 'Hi', name: 'ada'),
                  const SystemMessage(id: 's', content: 'Be', name: 'sys'),
                  const DeveloperMessage(id: 'd', content: 'De', name: 'dev'),
                ],
              ),
              'u',
              TextMessageRole.user,
              '!',
            ),
            's',
            TextMessageRole.system,
            ' nice',
          ),
          'd',
          TextMessageRole.developer,
          'bug',
        );

        expect(next.messages, [
          isA<UserMessage>()
              .having((m) => m.content, 'content', 'Hi!')
              .having((m) => m.name, 'name', 'ada'),
          isA<SystemMessage>()
              .having((m) => m.content, 'content', 'Be nice')
              .having((m) => m.name, 'name', 'sys'),
          isA<DeveloperMessage>()
              .having((m) => m.content, 'content', 'Debug')
              .having((m) => m.name, 'name', 'dev'),
        ]);
      });

      test('leaves a message that is not text unchanged', () {
        const tool = ToolMessage(id: 'x', content: 'result', toolCallId: 'c');

        final next = mapper.append(
          state.copyWith(messages: const [tool]),
          'x',
          TextMessageRole.assistant,
          'Hi',
        );

        expect(next.messages.single, tool);
      });
    });

    group('appendChunk', () {
      test('appends to the message with the id', () {
        final next = mapper.appendChunk(state, 'm1', null, 'Hi');

        expect(
          next.messages.single,
          isA<AssistantMessage>()
              .having((m) => m.id, 'id', 'm1')
              .having((m) => m.content, 'content', 'Hi'),
        );
      });

      for (final role in TextMessageRole.values) {
        test('without an id continues the last ${role.name} message', () {
          final started = mapper.appendChunk(state, 'm1', role, 'Hi');

          final next = mapper.appendChunk(started, null, role, '!');

          expect(next.messages.single.content, 'Hi!');
        });
      }

      test('without an id or a role continues an assistant message', () {
        final started = mapper.appendChunk(state, 'm1', null, 'Hi');

        final next = mapper.appendChunk(started, null, null, '!');

        expect(next.messages.single.content, 'Hi!');
      });

      test('without an id never grows a message of another role', () {
        final from = state.copyWith(messages: [user]);

        expect(mapper.appendChunk(from, null, null, 'x'), from);
      });

      test('without an id or a prior message is ignored', () {
        expect(mapper.appendChunk(state, null, null, 'x'), state);
      });
    });
  });
}
