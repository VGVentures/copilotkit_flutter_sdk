import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(FrontendTool, () {
    test('exposes its fields and runs its handler', () async {
      final parameters = Ack.object({'city': Ack.string()});
      final tool = FrontendTool(
        name: 'showWeather',
        description: 'Show the weather for a city',
        parameters: parameters,
        handler: (args, {required signal}) async => 'sunny in ${args['city']}',
      );

      expect(tool.name, 'showWeather');
      expect(tool.description, 'Show the weather for a city');
      expect(tool.parameters, same(parameters));
      expect(
        await tool.handler({'city': 'Lima'}, signal: CancellationSignal()),
        'sunny in Lima',
      );
    });
  });

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

  group(CancellationSignal, () {
    test('starts not cancelled', () {
      expect(CancellationSignal().isCancelled, isFalse);
    });

    test('cancel marks it cancelled and completes whenCancelled', () async {
      final signal = CancellationSignal()..cancel();

      expect(signal.isCancelled, isTrue);
      await expectLater(signal.whenCancelled, completes);
    });

    test('cancel twice has no effect', () {
      final signal = CancellationSignal()
        ..cancel()
        ..cancel();

      expect(signal.isCancelled, isTrue);
    });
  });
}
