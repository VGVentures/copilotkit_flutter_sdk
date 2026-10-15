import 'package:copilotkit/copilotkit.dart';
import 'package:test/test.dart';

void main() {
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
