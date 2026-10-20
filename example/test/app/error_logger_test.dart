import 'package:example/app/error_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(ErrorLogger, () {
    test('logs errors instead of throwing them', () {
      expect(
        () => const ErrorLogger()(Exception('logged'), StackTrace.current),
        returnsNormally,
      );
    });
  });
}
