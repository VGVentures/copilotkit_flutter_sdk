import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(ThreadsEvent, () {
    test('events with no data are all equal to their kind', () {
      expect(const ThreadsRequested(), const ThreadsRequested());
      expect(
        const ThreadsNextPageRequested(),
        const ThreadsNextPageRequested(),
      );
      expect(const ThreadsRequested(), isNot(const ThreadsNextPageRequested()));
      expect(const ThreadsRequested().props, isEmpty);
      expect(const ThreadsNextPageRequested().props, isEmpty);
    });

    test('a rename is equal for the same thread and name', () {
      expect(const ThreadRenamed('t', 'n'), const ThreadRenamed('t', 'n'));
      expect(
        const ThreadRenamed('t', 'n'),
        isNot(const ThreadRenamed('t', 'm')),
      );
      expect(
        const ThreadRenamed('t', 'n'),
        isNot(const ThreadRenamed('u', 'n')),
      );
    });

    test('archive, unarchive and delete are equal for the same thread', () {
      expect(const ThreadArchived('t'), const ThreadArchived('t'));
      expect(const ThreadArchived('t'), isNot(const ThreadArchived('u')));
      expect(const ThreadUnarchived('t'), const ThreadUnarchived('t'));
      expect(const ThreadUnarchived('t'), isNot(const ThreadUnarchived('u')));
      expect(const ThreadDeleted('t'), const ThreadDeleted('t'));
      expect(const ThreadDeleted('t'), isNot(const ThreadDeleted('u')));
    });
  });
}
