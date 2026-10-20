import 'package:ag_ui/ag_ui.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

void main() {
  group('fixtures', () {
    const names = [
      'text_stream',
      'frontend_tool_call',
      'state_snapshot_delta',
      'run_error',
      'unknown_events',
      'dropped_connection',
    ];

    for (final name in names) {
      test('$name has a header and starts with RUN_STARTED', () {
        final fixture = Fixture.load(name);

        expect(fixture.header['source'], anyOf('recorded', 'synthetic'));
        expect(fixture.events.first, isA<RunStartedEvent>());
      });
    }

    test('recorded fixtures decode completely', () {
      for (final name in [
        'text_stream',
        'frontend_tool_call',
        'state_snapshot_delta',
        'run_error',
      ]) {
        final fixture = Fixture.load(name);

        expect(fixture.isSynthetic, isFalse, reason: name);
        expect(fixture.undecodable, isEmpty, reason: name);
      }
    });

    test('unknown_events only drops the event type ag_ui does not know', () {
      final fixture = Fixture.load('unknown_events');

      expect(fixture.isSynthetic, isTrue);
      expect(fixture.undecodable, [containsPair('type', 'SUBAGENT_STARTED')]);
      expect(fixture.events.last, isA<RunFinishedEvent>());
    });

    test('dropped_connection ends without a terminal event', () {
      final fixture = Fixture.load('dropped_connection');

      expect(fixture.isSynthetic, isTrue);
      expect(fixture.events.last, isA<TextMessageContentEvent>());
    });
  });
}
