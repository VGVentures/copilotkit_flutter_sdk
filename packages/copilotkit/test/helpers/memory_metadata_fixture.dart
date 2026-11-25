import 'package:phoenix_channels_client/phoenix_channels_client.dart';

import 'fixtures.dart';

/// The rows of `memory_metadata_channel.jsonl`, which is recorded.
List<Map<String, Object?>> _rows() =>
    loadFixture('memory_metadata_channel').rawEvents;

/// The recorded response body of the http [step] of the channel fixture.
Object? memoryChannelBody(String step) => _rows().firstWhere(
  (row) => row['kind'] == 'http' && row['step'] == step,
)['body'];

/// The payload of the first recorded `memory_metadata` frame of [operation].
Map<String, Object?> memoryMetadataPayload(String operation) =>
    _rows().firstWhere(
          (row) =>
              row['kind'] == 'frame' &&
              (row['payload']! as Map)['operation'] == operation,
        )['payload']!
        as Map<String, Object?>;

/// Every recorded frame, in order, as the Phoenix client emits it.
List<PhoenixEvent> memoryMetadataFrames() => [
  for (final row in _rows())
    if (row['kind'] == 'frame')
      PhoenixEvent(
        topic: row['topic']! as String,
        event: row['event']! as String,
        payload: row['payload']! as Map<String, Object?>,
      ),
];
