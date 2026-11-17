import 'package:copilotkit/src/transport/models/thread_locked_exception.dart';
import 'package:test/test.dart';

void main() {
  group(ThreadLockedException, () {
    test('says what the runtime said', () {
      expect(
        const ThreadLockedException(message: 'Thread lock denied').toString(),
        'ThreadLockedException: Thread lock denied',
      );
    });

    test('has a message of its own when the runtime said nothing', () {
      expect(
        const ThreadLockedException().toString(),
        contains('already has a run going'),
      );
    });

    test('supports value equality', () {
      expect(
        const ThreadLockedException(message: 'a'),
        ThreadLockedException(message: String.fromCharCode(97)),
      );
      expect(
        const ThreadLockedException(message: 'a'),
        isNot(const ThreadLockedException()),
      );
    });
  });
}
