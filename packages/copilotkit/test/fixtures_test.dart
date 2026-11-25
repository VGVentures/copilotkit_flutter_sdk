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
      'connect_replay',
      'document_state_stream',
    ];

    for (final name in names) {
      test('$name has a header and starts with RUN_STARTED', () {
        final fixture = loadFixture(name);

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
        final fixture = loadFixture(name);

        expect(fixture.isSynthetic, isFalse, reason: name);
        expect(fixture.undecodable, isEmpty, reason: name);
      }
    });

    test('unknown_events only drops the event type ag_ui does not know', () {
      final fixture = loadFixture('unknown_events');

      expect(fixture.isSynthetic, isTrue);
      expect(fixture.undecodable, [containsPair('type', 'SUBAGENT_STARTED')]);
      expect(fixture.events.last, isA<RunFinishedEvent>());
    });

    test('connect_replay replays two finished runs', () {
      final fixture = loadFixture('connect_replay');

      expect(fixture.isSynthetic, isFalse);
      expect(fixture.undecodable, isEmpty);
      expect(fixture.events.whereType<RunStartedEvent>(), hasLength(2));
      expect(fixture.events.whereType<RunFinishedEvent>(), hasLength(2));
    });

    test('document_state_stream grows the document snapshot by snapshot', () {
      final fixture = loadFixture('document_state_stream');
      final documents = [
        for (final event in fixture.events.whereType<StateSnapshotEvent>())
          (event.snapshot as Map<String, Object?>)['document']! as String,
      ];

      expect(fixture.isSynthetic, isFalse);
      expect(fixture.undecodable, isEmpty);
      expect(documents.length, greaterThan(1));
      for (final (index, document) in documents.indexed.skip(1)) {
        expect(document, startsWith(documents[index - 1]));
      }
      expect(fixture.events.last, isA<RunFinishedEvent>());
    });

    test('dropped_connection ends without a terminal event', () {
      final fixture = loadFixture('dropped_connection');

      expect(fixture.isSynthetic, isTrue);
      expect(fixture.events.last, isA<TextMessageContentEvent>());
    });
  });
}
