// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/intelligence_connect_credentials.dart';
import 'package:copilotkit/src/transport/models/intelligence_realtime.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group(IntelligenceConnectCredentials, () {
    test('decodes the connect response of a recorded runtime', () {
      final connect = loadFixture('intelligence_connect_replay').rawEvents
          .firstWhere((row) => row['kind'] == 'http');

      final credentials = IntelligenceConnectCredentials.fromJson(
        connect['body']! as Map<String, Object?>,
      );

      expect(credentials.threadId, isNotEmpty);
      expect(credentials.joinToken, '<redacted>');
      expect(
        credentials.realtime.clientUrl,
        'wss://realtime.intelligence.copilotkit.ai/client',
      );
      expect(credentials.realtime.topic, 'thread:${credentials.threadId}');
    });

    test('ignores fields it does not know', () {
      final credentials = IntelligenceConnectCredentials.fromJson(const {
        'threadId': 't',
        'joinToken': 'j',
        'realtime': {'clientUrl': 'wss://x/client', 'topic': 'thread:t'},
        'somethingNew': true,
      });

      expect(credentials.threadId, 't');
    });

    test('throws when a field is missing', () {
      expect(
        () => IntelligenceConnectCredentials.fromJson(const {
          'threadId': 't',
          'realtime': {'clientUrl': 'wss://x/client', 'topic': 'thread:t'},
        }),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });

    test('supports value equality', () {
      const credentials = IntelligenceConnectCredentials(
        threadId: 't',
        joinToken: 'j',
        realtime: IntelligenceRealtime(clientUrl: 'u', topic: 't'),
      );

      expect(
        credentials,
        IntelligenceConnectCredentials(
          threadId: String.fromCharCode(116),
          joinToken: 'j',
          realtime: const IntelligenceRealtime(clientUrl: 'u', topic: 't'),
        ),
      );
      expect(
        credentials,
        isNot(
          const IntelligenceConnectCredentials(
            threadId: 't',
            joinToken: 'other',
            realtime: IntelligenceRealtime(clientUrl: 'u', topic: 't'),
          ),
        ),
      );
    });
  });
}
