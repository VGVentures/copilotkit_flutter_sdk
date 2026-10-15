import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final user = UserMessage(id: 'u1', content: 'hi');
  const call = ToolCallView(
    id: 'call-1',
    name: 'showWeather',
    status: ToolCallStatus.complete,
  );

  group(ChatRow, () {
    test('rows support value equality', () {
      // Non-const instances, so equality goes through props.
      // ignore_for_file: prefer_const_constructors
      expect(ChatMessageRow(user), ChatMessageRow(user));
      expect(
        ChatMessageRow(user),
        isNot(ChatMessageRow(UserMessage(id: 'u2', content: 'hi'))),
      );
      expect(ChatToolCallRow(call), ChatToolCallRow(call));
    });
  });
}
