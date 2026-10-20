import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const agentState = CopilotAgentState(agentId: 'default', threadId: 't');
  final user = UserMessage(id: 'u1', content: 'Weather in Lima?');
  const assistant = AssistantMessage(id: 'a1', content: 'Let me check');
  const call = ToolCallView(
    id: 'c1',
    name: 'showWeather',
    status: ToolCallStatus.executing,
    args: JsonObject({'city': 'Lima'}),
  );

  group(CopilotChatState, () {
    group('fromAgentState', () {
      test('copies isRunning and error', () {
        final state = CopilotChatState.fromAgentState(
          agentState.copyWith(isRunning: true, error: () => 'boom'),
        );

        expect(state, const CopilotChatState(isRunning: true, error: 'boom'));
      });

      test('hides tool, system and empty messages', () {
        final rows = CopilotChatState.fromAgentState(
          agentState.copyWith(
            messages: [
              const SystemMessage(id: 's', content: 'Be nice'),
              user,
              const AssistantMessage(id: 'empty', content: ''),
              const AssistantMessage(id: 'none'),
              const ToolMessage(id: 't', content: 'ok', toolCallId: 'c'),
              UserMessage(id: 'blank', content: ''),
              assistant,
            ],
          ),
        ).rows;

        expect(rows, [ChatMessageRow(user), const ChatMessageRow(assistant)]);
      });

      test('shows tool calls after their message, even without text', () {
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
          agentState.copyWith(messages: [callOnly], toolCalls: [call]),
        ).rows;

        expect(rows, [const ChatToolCallRow(call)]);
      });
    });
  });
}
