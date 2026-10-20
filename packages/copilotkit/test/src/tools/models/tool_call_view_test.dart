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
      expect(view.args, const JsonObject());
      expect(view.result, isNull);
      expect(view.awaitingResponse, isFalse);
    });

    test('holds args and result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: JsonObject({'city': 'Lima'}),
        result: 'sunny',
      );

      expect(view.args, const JsonObject({'city': 'Lima'}));
      expect(view.result, 'sunny');
    });

    test('supports value equality', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: JsonObject({'city': 'Lima'}),
        result: 'sunny',
      );

      expect(
        view,
        const ToolCallView(
          id: 'call-1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
          args: JsonObject({'city': 'Lima'}),
          result: 'sunny',
        ),
      );
      expect(view, isNot(view.copyWith(status: ToolCallStatus.executing)));
      expect(
        view,
        isNot(view.copyWith(args: const JsonObject({'city': 'Quito'}))),
      );
      expect(view, isNot(view.copyWith(awaitingResponse: true)));
    });

    group('copyWith', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.inProgress,
        args: JsonObject({'city': 'Lima'}),
        result: 'partial',
      );

      test('keeps every field when nothing is passed', () {
        expect(view.copyWith(), view);
      });

      test('replaces the given fields', () {
        final copy = view.copyWith(
          status: ToolCallStatus.complete,
          args: const JsonObject({'city': 'Quito'}),
          result: () => 'sunny',
        );

        expect(copy.id, 'call-1');
        expect(copy.name, 'showWeather');
        expect(copy.status, ToolCallStatus.complete);
        expect(copy.args, const JsonObject({'city': 'Quito'}));
        expect(copy.result, 'sunny');
      });

      test('can set and clear awaitingResponse', () {
        final waiting = view.copyWith(awaitingResponse: true);

        expect(waiting.awaitingResponse, isTrue);
        expect(waiting.copyWith().awaitingResponse, isTrue);
        expect(
          waiting.copyWith(awaitingResponse: false).awaitingResponse,
          isFalse,
        );
      });

      test('can clear the result', () {
        expect(view.copyWith(result: () => null).result, isNull);
      });
    });
  });
}
