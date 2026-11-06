import 'package:ag_ui/ag_ui.dart';
import 'package:copilotkit/src/transport/intelligence_event_decoder.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../helpers/fixtures.dart';

class _MockEventDecoder extends Mock implements EventDecoder;

void main() {
  group(IntelligenceEventDecoder, () {
    const decoder = IntelligenceEventDecoder();

    Map<String, Object?> payloadOf(String fixture, String type) {
      final frames = loadFixture(fixture).rawEvents
          .where((row) => row['event'] == 'ag_ui_event');
      return frames
          .map((row) => row['payload']! as Map<String, Object?>)
          .firstWhere((payload) => payload['type'] == type);
    }

    test('decodes every recorded event of every Intelligence run', () {
      for (final name in [
        'intelligence_text_run',
        'intelligence_tool_run',
        'intelligence_stop_rest',
        'intelligence_stop_channel',
        'intelligence_thread_locked',
      ]) {
        final payloads = loadFixture(name).rawEvents
            .where((row) => row['event'] == 'ag_ui_event')
            .map((row) => row['payload']! as Map<String, Object?>);

        expect(payloads, isNotEmpty, reason: name);
        for (final payload in payloads) {
          expect(() => decoder(payload), returnsNormally, reason: name);
        }
      }
    });

    group('what it hands to ag_ui', () {
      late _MockEventDecoder agUi;

      setUp(() {
        agUi = _MockEventDecoder();
        when(() => agUi.decodeJson(any()))
            .thenReturn(RunStartedEvent(threadId: 't', runId: 'r'));
      });

      Map<String, dynamic> handedOver() =>
          verify(() => agUi.decodeJson(captureAny())).captured.single
              as Map<String, dynamic>;

      test('has no routing fields and no Intelligence metadata', () {
        IntelligenceEventDecoder(decoder: agUi)(
          payloadOf('intelligence_text_run', 'RUN_STARTED'),
        );

        final json = handedOver();
        for (final field in IntelligenceEventDecoder.routingFields) {
          expect(json, isNot(contains(field)), reason: field);
        }
        expect(json, isNot(contains('metadata')));
        expect(json['type'], 'RUN_STARTED');
      });

      test('keeps the metadata the agent put there', () {
        IntelligenceEventDecoder(decoder: agUi)(
          payloadOf('intelligence_tool_run', 'RUN_FINISHED'),
        );

        expect(handedOver()['metadata'], {'finishReason': 'tool-calls'});
      });
    });

    test('throws on an event type ag_ui does not know', () {
      expect(
        () => decoder(const {'type': 'SOMETHING_NEW'}),
        throwsA(isA<DecodingError>()),
      );
    });
  });
}
