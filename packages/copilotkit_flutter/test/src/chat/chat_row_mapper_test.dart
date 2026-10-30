import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agentState = CopilotAgentState(agentId: 'default', threadId: 't');
  const user = UserMessage(id: 'u1', content: 'Weather in Lima?');
  const assistant = AssistantMessage(id: 'a1', content: 'Let me check');
  const call = ToolCallView(
    id: 'c1',
    name: 'showWeather',
    status: ToolCallStatus.executing,
    args: {'city': 'Lima'},
  );

  group(ChatRowMapper, () {
    const mapper = ChatRowMapper();

    test('hides tool, system, unsupported and empty messages', () {
      final rows = mapper(
        agentState.copyWith(
          messages: [
            const SystemMessage(id: 's', content: 'Be nice'),
            user,
            const AssistantMessage(id: 'empty', content: ''),
            const AssistantMessage(id: 'none'),
            const ToolMessage(id: 't', content: 'ok', toolCallId: 'c'),
            const DeveloperMessage(id: 'd', content: 'Debug'),
            const UnsupportedMessage(
              id: 'r',
              data: {'id': 'r', 'role': 'reasoning', 'content': 'Hmm'},
            ),
            const UserMessage(id: 'blank', content: ''),
            assistant,
          ],
        ),
      );

      expect(rows, [
        const ChatMessageRow(user),
        const ChatMessageRow(assistant),
      ]);
    });

    test('shows tool calls after their message, even without text', () {
      const callOnly = AssistantMessage(
        id: 'a2',
        toolCalls: [
          ToolCall(id: 'c1', name: 'showWeather', arguments: '{}'),
          ToolCall(id: 'unknown', name: 'other', arguments: '{}'),
        ],
      );

      final rows = mapper(
        agentState.copyWith(messages: [callOnly], toolCalls: [call]),
      );

      expect(rows, [const ChatToolCallRow(call)]);
    });
  });
}
