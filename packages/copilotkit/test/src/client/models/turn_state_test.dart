// Subscriptions on empty streams, held only as state handles.
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:copilotkit/src/client/models/run_state.dart';
import 'package:copilotkit/src/client/models/turn_state.dart';
import 'package:test/test.dart';

void main() {
  group(TurnState, () {
    final signal = CancellationSignal();
    final subscription = const Stream<BaseEvent>.empty().listen(null);
    final run = RunState(
      runId: 'r1',
      headers: const {'Authorization': 'Bearer t'},
      subscription: subscription,
    );

    test('supports value equality', () {
      expect(TurnState(signal: signal), TurnState(signal: signal));
      expect(
        TurnState(signal: signal, run: run),
        isNot(TurnState(signal: signal)),
      );
      expect(
        TurnState(signal: signal),
        isNot(TurnState(signal: CancellationSignal())),
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
