import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(ToolCallView, () {
    test('defaults to empty args and no result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.inProgress,
      );

      expect(view.id, 'call-1');
      expect(view.name, 'showWeather');
      expect(view.status, ToolCallStatus.inProgress);
      expect(view.args, isEmpty);
      expect(view.result, isNull);
    });

    test('holds args and result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: {'city': 'Lima'},
        result: 'sunny',
      );

      expect(view.args, {'city': 'Lima'});
      expect(view.result, 'sunny');
    });
  });
}
