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
      expect(view.args, const <String, Object?>{});
      expect(view.result, isNull);
      expect(view.awaitingResponse, isFalse);
    });

    test('holds args and result', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: {'city': 'Lima'},
        result: 'sunny',
      );

      expect(view.args, const {'city': 'Lima'});
      expect(view.result, 'sunny');
    });

    test('supports value equality', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.complete,
        args: {'city': 'Lima'},
        result: 'sunny',
      );

      expect(
        view,
        const ToolCallView(
          id: 'call-1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
          args: {'city': 'Lima'},
          result: 'sunny',
        ),
      );
      expect(view, isNot(view.copyWith(status: ToolCallStatus.executing)));
      expect(view, isNot(view.copyWith(args: const {'city': 'Quito'})));
      expect(view, isNot(view.copyWith(awaitingResponse: true)));
    });

    group('status getters', () {
      ToolCallView view(ToolCallStatus status) =>
          ToolCallView(id: 'call-1', name: 'showWeather', status: status);

      test('say which status the call is in', () {
        expect(view(ToolCallStatus.inProgress).isInProgress, isTrue);
        expect(view(ToolCallStatus.inProgress).isExecuting, isFalse);
        expect(view(ToolCallStatus.executing).isExecuting, isTrue);
        expect(view(ToolCallStatus.executing).isComplete, isFalse);
        expect(view(ToolCallStatus.complete).isComplete, isTrue);
        expect(view(ToolCallStatus.complete).isInProgress, isFalse);
      });
    });

    group('markedExecuting', () {
      test('moves a call in progress to executing', () {
        const view = ToolCallView(
          id: 'call-1',
          name: 'showWeather',
          status: ToolCallStatus.inProgress,
        );

        expect(
          view.markedExecuting(),
          view.copyWith(status: ToolCallStatus.executing),
        );
      });

      test('keeps a call past in progress', () {
        const view = ToolCallView(
          id: 'call-1',
          name: 'showWeather',
          status: ToolCallStatus.complete,
        );

        expect(view.markedExecuting(), view);
      });
    });

    group('markedAwaiting', () {
      test('marks an executing call as awaiting a response', () {
        const view = ToolCallView(
          id: 'call-1',
          name: 'confirmAction',
          status: ToolCallStatus.executing,
        );

        expect(view.markedAwaiting().awaitingResponse, isTrue);
      });

      test('keeps a call that is not executing', () {
        const view = ToolCallView(
          id: 'call-1',
          name: 'confirmAction',
          status: ToolCallStatus.inProgress,
        );

        expect(view.markedAwaiting(), view);
      });
    });

    group('completed', () {
      test('completes the call with its result and stops awaiting', () {
        const view = ToolCallView(
          id: 'call-1',
          name: 'confirmAction',
          status: ToolCallStatus.executing,
          awaitingResponse: true,
        );

        expect(
          view.completed('yes'),
          const ToolCallView(
            id: 'call-1',
            name: 'confirmAction',
            status: ToolCallStatus.complete,
            result: 'yes',
          ),
        );
      });
    });

    group('copyWith', () {
      const view = ToolCallView(
        id: 'call-1',
        name: 'showWeather',
        status: ToolCallStatus.inProgress,
        args: {'city': 'Lima'},
        result: 'partial',
      );

      test('keeps every field when nothing is passed', () {
        expect(view.copyWith(), view);
      });

      test('replaces the given fields', () {
        final copy = view.copyWith(
          status: ToolCallStatus.complete,
          args: const {'city': 'Quito'},
          result: () => 'sunny',
        );

        expect(copy.id, 'call-1');
        expect(copy.name, 'showWeather');
        expect(copy.status, ToolCallStatus.complete);
        expect(copy.args, const {'city': 'Quito'});
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
