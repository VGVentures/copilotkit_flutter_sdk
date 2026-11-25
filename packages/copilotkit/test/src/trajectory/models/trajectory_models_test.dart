// cspell:ignore realtime
import 'package:copilotkit/src/trajectory/trajectory.dart';
import 'package:test/test.dart';

import '../../../helpers/trajectory_fixture.dart';

void main() {
  group(TrajectoryGrant, () {
    test('decodes the recorded grant', () {
      final grant = TrajectoryGrant.fromJson(
        trajectoryRow('connect')['body']! as Map<String, Object?>,
      );

      expect(grant.joinToken, '<redacted>');
      expect(
        grant.clientUrl,
        Uri.parse('wss://realtime.intelligence.copilotkit.ai/client'),
      );
      expect(grant.topic, startsWith('trajectory:'));
      expect(
        grant,
        TrajectoryGrant.fromJson(
          trajectoryRow('connect')['body']! as Map<String, Object?>,
        ),
      );
    });

    test('rejects a body that is not a grant', () {
      for (final json in [
        <String, Object?>{},
        {
          'joinToken': '',
          'realtime': {'clientUrl': 'wss://x', 'topic': 't'},
        },
        {
          'joinToken': 't',
          'realtime': {'clientUrl': 'wss://x'},
        },
      ]) {
        expect(() => TrajectoryGrant.fromJson(json), throwsFormatException);
      }
    });
  });

  group(TrajectoryReceipt, () {
    Object? reply(String step) => trajectoryRow(step)['response'];

    test('reads the synthetic receipts', () {
      expect(
        TrajectoryReceipt.tryParse(reply('batch'), 2),
        isA<TrajectoryReceipt>()
            .having((r) => r.accepted, 'accepted', 2)
            .having((r) => r.highestSeq, 'highestSeq', 1764100000000001),
      );
      expect(
        TrajectoryReceipt.tryParse(reply('partly-rejected'), 2)?.rejected,
        1,
      );
      expect(
        TrajectoryReceipt.tryParse(reply('dropped-only'), 0),
        const TrajectoryReceipt(accepted: 0, rejected: 0),
      );
    });

    test('is null for a reply that is not a receipt for the batch', () {
      for (final (reply, size) in [
        (null, 0),
        (const {'accepted': 1, 'rejected': 0, 'highestSeq': 5}, 2),
        (const {'accepted': -1, 'rejected': 1, 'highestSeq': 5}, 0),
        (const {'accepted': 1, 'rejected': 0}, 1),
        (const {'accepted': 1, 'rejected': 0, 'highestSeq': '5'}, 1),
        (const {'accepted': 0, 'rejected': 0, 'highestSeq': -1}, 0),
      ]) {
        expect(
          TrajectoryReceipt.tryParse(reply, size),
          isNull,
          reason: '$reply',
        );
      }
    });
  });

  group(TrajectoryException, () {
    test('describes itself and compares by value', () {
      const error = TrajectoryException(code: 'EVENTS_DROPPED', message: 'x');

      expect(error.toString(), 'TrajectoryException(EVENTS_DROPPED): x');
      expect(error.isRetryable, isFalse);
      expect(
        TrajectoryException(
          code: 'A',
          message: 'm',
          statusCode: int.parse('503'),
        ),
        const TrajectoryException(code: 'A', message: 'm', statusCode: 503),
      );
    });
  });

  group(TrajectoryBuiltInEvent, () {
    test('reserves the names of the built-in events', () {
      expect(TrajectoryBuiltInEvent.values.map((event) => event.wireName), [
        'page',
        'navigation',
        'click',
        'input',
        'network',
        'thread.linked',
        'agent.run',
        'agent.message',
        'tool.call',
      ]);
      expect(TrajectoryBuiltInEvent.isReserved('thread.linked'), isTrue);
      expect(TrajectoryBuiltInEvent.isReserved('deal.approved'), isFalse);
    });
  });
}
