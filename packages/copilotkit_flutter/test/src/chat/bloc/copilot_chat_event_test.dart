import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(CopilotChatEvent, () {
    test('supports value equality', () {
      // Non-const instances, so equality goes through props.
      // ignore_for_file: prefer_const_constructors
      expect(ChatMessageSent('a'), ChatMessageSent('a'));
      expect(ChatMessageSent('a'), isNot(ChatMessageSent('b')));
      expect(ChatStopRequested(), ChatStopRequested());
      expect(ChatSubscriptionRequested(), ChatSubscriptionRequested());
    });
  });
}
