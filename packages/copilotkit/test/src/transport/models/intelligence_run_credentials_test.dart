// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/intelligence_realtime.dart';
import 'package:copilotkit/src/transport/models/intelligence_run_credentials.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group(IntelligenceRunCredentials, () {
    test('decodes the run response of a recorded Intelligence runtime', () {
      final run = loadFixture('intelligence_text_run').rawEvents
          .firstWhere((row) => row['step'] == 'run');

      final credentials = IntelligenceRunCredentials.fromJson(
        run['body']! as Map<String, Object?>,
      );

      expect(credentials.threadId, '8a8caab5-178f-469c-b719-6edb80b27621');
      expect(credentials.runId, '02ae5866-63ea-4e1f-923a-a53809f2f30f');
      expect(credentials.joinToken, '<redacted>');
      expect(
        credentials.realtime,
        const IntelligenceRealtime(
          clientUrl: 'wss://realtime.intelligence.copilotkit.ai/client',
          topic: 'thread:8a8caab5-178f-469c-b719-6edb80b27621',
        ),
      );
    });

    test('ignores fields it does not know', () {
      final credentials = IntelligenceRunCredentials.fromJson(const {
        'threadId': 't',
        'runId': 'r',
        'joinToken': 'j',
        'realtime': {'clientUrl': 'wss://x/client', 'topic': 'thread:t'},
        'somethingNew': true,
      });

      expect(credentials.runId, 'r');
    });

    test('throws when a field is missing', () {
      expect(
        () => IntelligenceRunCredentials.fromJson(const {
          'threadId': 't',
          'runId': 'r',
          'realtime': {'clientUrl': 'wss://x/client', 'topic': 'thread:t'},
        }),
        throwsA(isA<CheckedFromJsonException>()),
      );
      expect(
        () => IntelligenceRealtime.fromJson(const {'clientUrl': 'wss://x'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('supports value equality', () {
      const realtime = IntelligenceRealtime(clientUrl: 'u', topic: 't');
      const credentials = IntelligenceRunCredentials(
        threadId: 't',
        runId: 'r',
        joinToken: 'j',
        realtime: realtime,
      );

      expect(
        credentials,
        IntelligenceRunCredentials(
          threadId: String.fromCharCode(116),
          runId: 'r',
          joinToken: 'j',
          realtime: const IntelligenceRealtime(clientUrl: 'u', topic: 't'),
        ),
      );
      expect(
        credentials,
        isNot(
          const IntelligenceRunCredentials(
            threadId: 't',
            runId: 'r2',
            joinToken: 'j',
            realtime: realtime,
          ),
        ),
      );
    });
  });
}
