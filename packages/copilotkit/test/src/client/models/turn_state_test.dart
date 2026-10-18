// Subscriptions on empty streams, held only as state handles.
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:test/test.dart';

void main() {
  group(TurnState, () {
    final controller = CancellationController();
    final subscription = const Stream<BaseEvent>.empty().listen(null);
    final run = RunState(
      runId: 'r1',
      headers: const {'Authorization': 'Bearer t'},
      subscription: subscription,
    );

    test('copyWith sets, keeps and clears the run', () {
      final turn = TurnState(controller: controller);

      final withRun = turn.copyWith(run: () => run);
      expect(withRun.controller, same(controller));
      expect(withRun.run, run);
      expect(withRun.copyWith().run, run);
      expect(withRun.copyWith(run: () => null).run, isNull);
    });

    test('toString leaves out the request headers', () {
      final turn = TurnState(controller: controller, run: run);

      expect(turn.toString(), isNot(contains('Bearer')));
      expect(run.toString(), isNot(contains('Bearer')));
    });

    test('supports value equality', () {
      expect(
        TurnState(controller: controller),
        TurnState(controller: controller),
      );
      expect(
        TurnState(controller: controller, run: run),
        isNot(TurnState(controller: controller)),
      );
      expect(
        TurnState(controller: controller),
        isNot(TurnState(controller: CancellationController())),
      );
    });
  });

  group(RunState, () {
    test('supports value equality by run id, headers and subscription', () {
      final subscription = const Stream<BaseEvent>.empty().listen(null);
      RunState run({String runId = 'r1'}) =>
          RunState(runId: runId, headers: const {}, subscription: subscription);

      expect(run(), run());
      expect(run(), isNot(run(runId: 'r2')));
      expect(
        run(),
        isNot(
          RunState(
            runId: 'r1',
            headers: const {},
            subscription: const Stream<BaseEvent>.empty().listen(null),
          ),
        ),
      );
    });
  });
}
