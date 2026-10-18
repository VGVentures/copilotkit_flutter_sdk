import 'dart:async';

import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
  group(CancellationController, () {
    test('starts not cancelled', () {
      final controller = CancellationController();

      expect(controller.isCancelled, isFalse);
      expect(controller.signal.isCancelled, isFalse);
    });

    test('cancel cancels the signal and completes whenCancelled', () async {
      final controller = CancellationController();
      final signal = controller.signal;

      controller.cancel();

      expect(controller.isCancelled, isTrue);
      expect(signal.isCancelled, isTrue);
      await expectLater(signal.whenCancelled, completes);
    });

    test('cancel twice has no effect', () {
      final controller = CancellationController()
        ..cancel()
        ..cancel();

      expect(controller.isCancelled, isTrue);
    });

    test('hands out the same signal every time', () {
      final controller = CancellationController();

      expect(controller.signal, same(controller.signal));
    });
  });

  group('CancellationSignal.none', () {
    test('is never cancelled', () async {
      const signal = CancellationSignal.none();

      expect(signal.isCancelled, isFalse);
      var completed = false;
      unawaited(signal.whenCancelled.then((_) => completed = true));
      await pumpEventQueue();
      expect(completed, isFalse);
    });
  });
}
