import 'package:copilotkit/src/tools/tools.dart';
import 'package:test/test.dart';

ToolCallView _view(ToolCallStatus status, {bool awaitingResponse = false}) =>
    ToolCallView(
      id: 'c1',
      name: 'showWeather',
      status: status,
      awaitingResponse: awaitingResponse,
    );

void main() {
  group('ToolCallViewTransitions', () {
    group('finishArgs', () {
      test('moves an in-progress view to executing', () {
        expect(
          _view(ToolCallStatus.inProgress).finishArgs(),
          _view(ToolCallStatus.executing),
        );
      });

      test('returns any other view unchanged', () {
        for (final status in [
          ToolCallStatus.executing,
          ToolCallStatus.complete,
        ]) {
          final view = _view(status);
          expect(view.finishArgs(), view);
        }
      });
    });

    group('awaitResponse', () {
      test('marks an executing view as awaiting a response', () {
        expect(
          _view(ToolCallStatus.executing).awaitResponse(),
          _view(ToolCallStatus.executing, awaitingResponse: true),
        );
      });

      test('returns any other view unchanged', () {
        for (final status in [
          ToolCallStatus.inProgress,
          ToolCallStatus.complete,
        ]) {
          final view = _view(status);
          expect(view.awaitResponse(), view);
        }
      });
    });

    test('complete sets the result and stops awaiting a response', () {
      final view = _view(
        ToolCallStatus.executing,
        awaitingResponse: true,
      ).complete('sunny');

      expect(view.status, ToolCallStatus.complete);
      expect(view.result, 'sunny');
      expect(view.awaitingResponse, isFalse);
    });
  });
}
