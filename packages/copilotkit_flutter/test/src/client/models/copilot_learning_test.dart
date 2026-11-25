import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(CopilotLearning, () {
    test('compares by value', () {
      expect(
        CopilotLearning(trajectoryId: int.parse('1').toString()),
        const CopilotLearning(trajectoryId: '1'),
      );
      expect(const CopilotLearning().trajectoryId, isNull);
    });
  });
}
