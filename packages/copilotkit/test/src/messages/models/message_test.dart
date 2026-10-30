import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:copilotkit/src/messages/messages.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group(Message, () {
    group(UserMessage, () {
      test('has no name or encrypted value by default', () {
        const message = UserMessage(id: 'm1', content: 'Hi');

        expect(message.name, isNull);
        expect(message.encryptedValue, isNull);
      });

      test('supports value equality', () {
        expect(
          const UserMessage(
            id: 'm1',
            content: 'Hi',
            name: 'Ana',
            encryptedValue: 'secret',
          ),
          UserMessage(
            id: 'm1',
            content: String.fromCharCodes('Hi'.codeUnits),
            name: 'Ana',
            encryptedValue: 'secret',
          ),
        );
        expect(
          const UserMessage(id: 'm1', content: 'Hi'),
          isNot(const UserMessage(id: 'm1', content: 'Hey')),
        );
      });
    });

    group(AssistantMessage, () {
      test('has no content and no tool calls by default', () {
        const message = AssistantMessage(id: 'm1');

        expect(message.content, isNull);
        expect(message.toolCalls, isEmpty);
        expect(message.name, isNull);
        expect(message.encryptedValue, isNull);
      });

      test('supports value equality', () {
        expect(
          const AssistantMessage(
            id: 'm1',
            content: 'Sure',
            toolCalls: [ToolCall(id: 'c1', name: 'show', arguments: '{}')],
            name: 'bot',
            encryptedValue: 'secret',
          ),
          AssistantMessage(
            id: 'm1',
            content: 'Sure',
            toolCalls: List.of(const [
              ToolCall(id: 'c1', name: 'show', arguments: '{}'),
            ]),
            name: 'bot',
            encryptedValue: 'secret',
          ),
        );
        expect(
          const AssistantMessage(id: 'm1'),
          isNot(
            const AssistantMessage(
              id: 'm1',
              toolCalls: [ToolCall(id: 'c1', name: 'show', arguments: '{}')],
            ),
          ),
        );
      });
      group('copyWith', () {
        const message = AssistantMessage(
          id: 'm1',
          content: 'Sure',
          toolCalls: [ToolCall(id: 'c1', name: 'show', arguments: '{}')],
          name: 'bot',
          encryptedValue: 'secret',
        );

        test('keeps every field when nothing is passed', () {
          expect(message.copyWith(), message);
        });

        test('replaces the given fields', () {
          expect(
            message.copyWith(content: () => 'Done', toolCalls: const []),
            const AssistantMessage(
              id: 'm1',
              content: 'Done',
              name: 'bot',
              encryptedValue: 'secret',
            ),
          );
        });

        test('can clear the content', () {
          expect(message.copyWith(content: () => null).content, isNull);
        });

        test('keeps the given tool calls unmodifiable', () {
          final toolCalls = [
            const ToolCall(id: 'c2', name: 'show', arguments: '{}'),
          ];
          final copy = message.copyWith(toolCalls: toolCalls);
          toolCalls.clear();

          expect(copy.toolCalls, hasLength(1));
          expect(
            () => copy.toolCalls.add(
              const ToolCall(id: 'c3', name: 'show', arguments: '{}'),
            ),
            throwsUnsupportedError,
          );
        });
      });
    });

    group(SystemMessage, () {
      test('has no name or encrypted value by default', () {
        const message = SystemMessage(id: 'm1', content: 'Be brief');

        expect(message.name, isNull);
        expect(message.encryptedValue, isNull);
      });

      test('supports value equality', () {
        expect(
          const SystemMessage(
            id: 'm1',
            content: 'Be brief',
            name: 'app',
            encryptedValue: 'secret',
          ),
          SystemMessage(
            id: 'm1',
            content: String.fromCharCodes('Be brief'.codeUnits),
            name: 'app',
            encryptedValue: 'secret',
          ),
        );
        expect(
          const SystemMessage(id: 'm1', content: 'Be brief'),
          isNot(const SystemMessage(id: 'm2', content: 'Be brief')),
        );
      });
    });

    group(DeveloperMessage, () {
      test('has no name or encrypted value by default', () {
        const message = DeveloperMessage(id: 'm1', content: 'Be brief');

        expect(message.name, isNull);
        expect(message.encryptedValue, isNull);
      });

      test('supports value equality', () {
        expect(
          const DeveloperMessage(
            id: 'm1',
            content: 'Be brief',
            name: 'dev',
            encryptedValue: 'secret',
          ),
          DeveloperMessage(
            id: 'm1',
            content: String.fromCharCodes('Be brief'.codeUnits),
            name: 'dev',
            encryptedValue: 'secret',
          ),
        );
        expect(
          const DeveloperMessage(id: 'm1', content: 'Be brief'),
          isNot(const SystemMessage(id: 'm1', content: 'Be brief')),
        );
      });
    });

    group(ToolMessage, () {
      test('has no error or encrypted value by default', () {
        const message = ToolMessage(
          id: 'm1',
          content: 'sunny',
          toolCallId: 'c1',
        );

        expect(message.error, isNull);
        expect(message.encryptedValue, isNull);
      });

      test('supports value equality', () {
        expect(
          const ToolMessage(
            id: 'm1',
            content: 'sunny',
            toolCallId: 'c1',
            error: 'timeout',
            encryptedValue: 'secret',
          ),
          ToolMessage(
            id: 'm1',
            content: String.fromCharCodes('sunny'.codeUnits),
            toolCallId: 'c1',
            error: 'timeout',
            encryptedValue: 'secret',
          ),
        );
        expect(
          const ToolMessage(id: 'm1', content: 'sunny', toolCallId: 'c1'),
          isNot(
            const ToolMessage(id: 'm1', content: 'sunny', toolCallId: 'c2'),
          ),
        );
      });
    });

    group(UnsupportedMessage, () {
      test('supports value equality', () {
        expect(
          const UnsupportedMessage(
            id: 'm1',
            data: {'id': 'm1', 'role': 'reasoning', 'content': 'Thinking'},
          ),
          UnsupportedMessage(
            id: 'm1',
            data: Map.of(const {
              'id': 'm1',
              'role': 'reasoning',
              'content': 'Thinking',
            }),
          ),
        );
        expect(
          const UnsupportedMessage(id: 'm1', data: {'role': 'reasoning'}),
          isNot(const UnsupportedMessage(id: 'm1', data: {'role': 'activity'})),
        );
      });
    });

    group('AG-UI conversion', () {
      const toolCall = ag_ui.ToolCall(
        id: 'c1',
        function: ag_ui.FunctionCall(
          name: 'showWeather',
          arguments: '{"city":"Lima"}',
        ),
        encryptedValue: 'call-secret',
      );

      final agUiMessages = <String, ag_ui.Message>{
        'user': ag_ui.UserMessage(id: 'm1', content: 'Hi'),
        'user with name and encrypted value': ag_ui.UserMessage(
          id: 'm1',
          content: 'Hi',
          name: 'Ana',
          encryptedValue: 'secret',
        ),
        'multimodal user': ag_ui.UserMessage.multimodal(
          id: 'm1',
          parts: const [
            ag_ui.TextInputContent('What is this?'),
            ag_ui.ImageInputContent(
              source: ag_ui.UrlSource(
                value: 'https://example.com/a.png',
                mimeType: 'image/png',
              ),
            ),
          ],
          encryptedValue: 'secret',
        ),
        'assistant with text': const ag_ui.AssistantMessage(
          id: 'm2',
          content: 'Hello',
        ),
        'assistant with tool calls': const ag_ui.AssistantMessage(
          id: 'm2',
          content: 'Checking',
          toolCalls: [toolCall],
          name: 'bot',
          encryptedValue: 'secret',
        ),
        'assistant with a non-function tool call': const ag_ui.AssistantMessage(
          id: 'm2',
          toolCalls: [
            ag_ui.ToolCall(
              id: 'c1',
              type: 'custom',
              function: ag_ui.FunctionCall(name: 'search', arguments: '{}'),
            ),
          ],
        ),
        'system': const ag_ui.SystemMessage(
          id: 'm3',
          content: 'Be brief',
          name: 'app',
          encryptedValue: 'secret',
        ),
        'developer': const ag_ui.DeveloperMessage(
          id: 'm4',
          content: 'Use metric units',
          name: 'dev',
          encryptedValue: 'secret',
        ),
        'tool': const ag_ui.ToolMessage(
          id: 'm5',
          content: 'sunny',
          toolCallId: 'c1',
          error: 'partial',
          encryptedValue: 'secret',
        ),
        'activity': const ag_ui.ActivityMessage(
          id: 'm6',
          activityType: 'search',
          activityContent: {'query': 'weather'},
        ),
        'reasoning': const ag_ui.ReasoningMessage(
          id: 'm7',
          content: 'Thinking',
          thinking: 'blob',
          encryptedValue: 'secret',
        ),
        'reasoning without id': const ag_ui.ReasoningMessage(content: 'Hmm'),
      };

      group('round-trips without losing data', () {
        for (final MapEntry(key: kind, value: message)
            in agUiMessages.entries) {
          test(kind, () {
            expect(
              Message.fromAgUi(message).toAgUi().toJson(),
              message.toJson(),
            );
          });
        }
      });

      test('sends an empty list of tool calls as no list', () {
        const message = ag_ui.AssistantMessage(id: 'm2', toolCalls: []);

        expect(Message.fromAgUi(message).toAgUi().toJson(), {
          'id': 'm2',
          'role': 'assistant',
        });
      });

      group('fromAgUi', () {
        test('creates a user message', () {
          expect(
            Message.fromAgUi(
              agUiMessages['user with name and encrypted value']!,
            ),
            const UserMessage(
              id: 'm1',
              content: 'Hi',
              name: 'Ana',
              encryptedValue: 'secret',
            ),
          );
        });

        test('creates an assistant message with flat tool calls', () {
          expect(
            Message.fromAgUi(agUiMessages['assistant with tool calls']!),
            const AssistantMessage(
              id: 'm2',
              content: 'Checking',
              toolCalls: [
                ToolCall(
                  id: 'c1',
                  name: 'showWeather',
                  arguments: '{"city":"Lima"}',
                  encryptedValue: 'call-secret',
                ),
              ],
              name: 'bot',
              encryptedValue: 'secret',
            ),
          );
        });

        test('keeps the tool calls of an assistant message unmodifiable', () {
          final message = Message.fromAgUi(
            agUiMessages['assistant with tool calls']!,
          ) as AssistantMessage;

          expect(message.toolCalls.clear, throwsUnsupportedError);
        });

        test('creates an assistant message without tool calls', () {
          expect(
            Message.fromAgUi(agUiMessages['assistant with text']!),
            const AssistantMessage(id: 'm2', content: 'Hello'),
          );
        });

        test('creates a system message', () {
          expect(
            Message.fromAgUi(agUiMessages['system']!),
            const SystemMessage(
              id: 'm3',
              content: 'Be brief',
              name: 'app',
              encryptedValue: 'secret',
            ),
          );
        });

        test('creates a developer message', () {
          expect(
            Message.fromAgUi(agUiMessages['developer']!),
            const DeveloperMessage(
              id: 'm4',
              content: 'Use metric units',
              name: 'dev',
              encryptedValue: 'secret',
            ),
          );
        });

        test('creates a tool message', () {
          expect(
            Message.fromAgUi(agUiMessages['tool']!),
            const ToolMessage(
              id: 'm5',
              content: 'sunny',
              toolCallId: 'c1',
              error: 'partial',
              encryptedValue: 'secret',
            ),
          );
        });

        test('keeps a message it cannot model as its JSON', () {
          final message = agUiMessages['reasoning']!;

          expect(
            Message.fromAgUi(message),
            UnsupportedMessage(id: 'm7', data: message.toJson()),
          );
        });

        for (final kind in [
          'multimodal user',
          'assistant with a non-function tool call',
          'activity',
        ]) {
          test('keeps the $kind message as an unsupported message', () {
            expect(
              Message.fromAgUi(agUiMessages[kind]!),
              isA<UnsupportedMessage>(),
            );
          });
        }

        test('generates an id for a message without one', () {
          final message = Message.fromAgUi(
            ag_ui.UserMessage(id: null, content: 'Hi'),
          );

          expect(message, isA<UserMessage>());
          expect(Uuid.isValidUUID(fromString: message.id), isTrue);
        });

        test('generates an id for an unsupported message without one', () {
          final message = Message.fromAgUi(
            agUiMessages['reasoning without id']!,
          );

          expect(
            message,
            isA<UnsupportedMessage>().having((m) => m.data, 'data', {
              'role': 'reasoning',
              'content': 'Hmm',
            }),
          );
          expect(Uuid.isValidUUID(fromString: message.id), isTrue);
        });

        test('keeps the data of an unsupported message unmodifiable', () {
          final message =
              Message.fromAgUi(agUiMessages['activity']!) as UnsupportedMessage;

          expect(() => message.data['id'] = 'x', throwsUnsupportedError);
        });
      });

      group('toAgUi', () {
        test('converts a user message', () {
          expect(
            const UserMessage(
              id: 'm1',
              content: 'Hi',
              name: 'Ana',
              encryptedValue: 'secret',
            ).toAgUi().toJson(),
            {
              'id': 'm1',
              'role': 'user',
              'content': 'Hi',
              'name': 'Ana',
              'encryptedValue': 'secret',
            },
          );
        });

        test('converts tool calls to function calls', () {
          expect(
            const AssistantMessage(
              id: 'm2',
              toolCalls: [
                ToolCall(id: 'c1', name: 'showWeather', arguments: '{}'),
              ],
            ).toAgUi().toJson(),
            {
              'id': 'm2',
              'role': 'assistant',
              'toolCalls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'showWeather', 'arguments': '{}'},
                },
              ],
            },
          );
        });

        test('converts an unsupported message back from its JSON', () {
          expect(
            const UnsupportedMessage(
              id: 'm7',
              data: {'id': 'm7', 'role': 'reasoning', 'content': 'Thinking'},
            ).toAgUi(),
            isA<ag_ui.ReasoningMessage>()
                .having((m) => m.id, 'id', 'm7')
                .having((m) => m.content, 'content', 'Thinking'),
          );
        });
      });
    });

    group('text', () {
      test('is the content of a text message', () {
        expect(const UserMessage(id: 'u', content: 'hi').text, 'hi');
        expect(
          const SystemMessage(id: 's', content: 'be brief').text,
          'be brief',
        );
        expect(
          const DeveloperMessage(id: 'd', content: 'be kind').text,
          'be kind',
        );
        expect(const AssistantMessage(id: 'a', content: 'hello').text, 'hello');
      });

      test('is null for an assistant message without content', () {
        expect(const AssistantMessage(id: 'a').text, isNull);
      });

      test('is null for tool results and unsupported messages', () {
        expect(
          const ToolMessage(id: 't', content: 'ok', toolCallId: 'c').text,
          isNull,
        );
        expect(const UnsupportedMessage(id: 'x', data: {}).text, isNull);
      });
    });

    group('textRole', () {
      test('is the role of the author of a text message', () {
        expect(
          const UserMessage(id: 'u', content: '').textRole,
          ag_ui.TextMessageRole.user,
        );
        expect(
          const AssistantMessage(id: 'a').textRole,
          ag_ui.TextMessageRole.assistant,
        );
        expect(
          const SystemMessage(id: 's', content: '').textRole,
          ag_ui.TextMessageRole.system,
        );
        expect(
          const DeveloperMessage(id: 'd', content: '').textRole,
          ag_ui.TextMessageRole.developer,
        );
      });

      test('is null for tool results and unsupported messages', () {
        expect(
          const ToolMessage(id: 't', content: 'ok', toolCallId: 'c').textRole,
          isNull,
        );
        expect(const UnsupportedMessage(id: 'x', data: {}).textRole, isNull);
      });
    });

    group('fromRole', () {
      test('creates the text message of each role', () {
        Message create(ag_ui.TextMessageRole role) =>
            Message.fromRole(role, id: 'm', content: 'hi', name: 'n');

        expect(
          create(ag_ui.TextMessageRole.user),
          const UserMessage(id: 'm', content: 'hi', name: 'n'),
        );
        expect(
          create(ag_ui.TextMessageRole.assistant),
          const AssistantMessage(id: 'm', content: 'hi', name: 'n'),
        );
        expect(
          create(ag_ui.TextMessageRole.system),
          const SystemMessage(id: 'm', content: 'hi', name: 'n'),
        );
        expect(
          create(ag_ui.TextMessageRole.developer),
          const DeveloperMessage(id: 'm', content: 'hi', name: 'n'),
        );
      });
    });

    group('appended', () {
      test('appends to the text of a text message, keeping its fields', () {
        expect(
          const UserMessage(
            id: 'u',
            content: 'he',
            name: 'n',
            encryptedValue: 'e',
          ).appended('llo'),
          const UserMessage(
            id: 'u',
            content: 'hello',
            name: 'n',
            encryptedValue: 'e',
          ),
        );
        expect(
          const SystemMessage(id: 's', content: 'a').appended('b'),
          const SystemMessage(id: 's', content: 'ab'),
        );
        expect(
          const DeveloperMessage(id: 'd', content: 'a').appended('b'),
          const DeveloperMessage(id: 'd', content: 'ab'),
        );
        expect(
          const AssistantMessage(id: 'a', content: 'a').appended('b'),
          const AssistantMessage(id: 'a', content: 'ab'),
        );
      });

      test('starts the text of an assistant message without content', () {
        expect(
          const AssistantMessage(id: 'a').appended('hi'),
          const AssistantMessage(id: 'a', content: 'hi'),
        );
      });

      test('keeps tool results and unsupported messages', () {
        const tool = ToolMessage(id: 't', content: 'ok', toolCallId: 'c');
        const unsupported = UnsupportedMessage(id: 'x', data: {});

        expect(tool.appended('!'), tool);
        expect(unsupported.appended('!'), unsupported);
      });
    });

    group('copyWith of text messages', () {
      test('keeps every field when nothing is passed', () {
        const user = UserMessage(
          id: 'u',
          content: 'hi',
          name: 'n',
          encryptedValue: 'e',
        );
        const system = SystemMessage(id: 's', content: 'hi', name: 'n');
        const developer = DeveloperMessage(id: 'd', content: 'hi', name: 'n');

        expect(user.copyWith(), user);
        expect(system.copyWith(), system);
        expect(developer.copyWith(), developer);
      });

      test('replaces the content', () {
        expect(
          const UserMessage(id: 'u', content: 'hi').copyWith(content: 'yo'),
          const UserMessage(id: 'u', content: 'yo'),
        );
      });
    });

    group('tool calls of an assistant message', () {
      const first = ToolCall(id: 'c1', name: 'a', arguments: '');
      const second = ToolCall(id: 'c2', name: 'b', arguments: '');
      const message = AssistantMessage(id: 'a', toolCalls: [first]);

      test('anyToolCall says whether it has a call', () {
        expect(message.anyToolCall('c1'), isTrue);
        expect(message.anyToolCall('c2'), isFalse);
      });

      test('toolCallAdded appends a call', () {
        expect(
          message.toolCallAdded(second),
          const AssistantMessage(id: 'a', toolCalls: [first, second]),
        );
      });

      test('toolCallReplaced replaces the call with the same id', () {
        const updated = ToolCall(id: 'c1', name: 'a', arguments: '{}');

        expect(
          message.toolCallAdded(second).toolCallReplaced(updated),
          const AssistantMessage(id: 'a', toolCalls: [updated, second]),
        );
      });
    });
  });
}
