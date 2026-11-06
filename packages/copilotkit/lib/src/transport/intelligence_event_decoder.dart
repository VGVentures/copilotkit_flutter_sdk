import 'package:ag_ui/ag_ui.dart';

/// Turns the payload of an `ag_ui_event` frame into an AG-UI event.
///
/// Intelligence adds routing fields to every event and keeps its bookkeeping
/// in `metadata`. This removes them first, so the event is the one the agent
/// emitted. Throws a [DecodingError] when the payload isn't an event `ag_ui`
/// knows.
class const IntelligenceEventDecoder({
  final EventDecoder _decoder = const EventDecoder(),
}) {
  /// Creates a decoder.
  this;

  /// The fields Intelligence adds to the event itself.
  static const routingFields = {
    'organization_id',
    'project_id',
    'protocolVersion',
    'run_id',
    'thread_id',
  };

  /// The prefix of the keys Intelligence adds to `metadata`.
  static const metadataPrefix = 'cpki_';

  /// Decodes [payload] without the Intelligence fields.
  BaseEvent call(Map<String, Object?> payload) {
    final json = {
      for (final entry in payload.entries)
        if (!routingFields.contains(entry.key)) entry.key: entry.value,
    };
    if (json['metadata'] case final Map<String, Object?> metadata) {
      final kept = {
        for (final entry in metadata.entries)
          if (!entry.key.startsWith(metadataPrefix)) entry.key: entry.value,
      };
      if (kept.isEmpty) {
        json.remove('metadata');
      } else {
        json['metadata'] = kept;
      }
    }
    return _decoder.decodeJson(json);
  }
}
