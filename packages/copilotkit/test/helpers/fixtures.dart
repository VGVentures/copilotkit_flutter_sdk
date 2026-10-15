import 'dart:convert';
import 'dart:io';

import 'package:ag_ui/ag_ui.dart';

/// A JSONL fixture of raw AG-UI events from `test/fixtures/`.
///
/// The first line is a `{"fixture": {...}}` header saying whether the events
/// were `recorded` from a runtime or written by hand (`synthetic`).
class Fixture({
  required final Map<String, Object?> header,
  required final List<Map<String, Object?>> rawEvents,
}) {
  /// Every event `ag_ui` can decode, in order. Undecodable events are
  /// skipped, like `AgUiTransport` does.
  late final List<BaseEvent> events = [
    for (final json in rawEvents) ?_decode(json),
  ];

  /// Raw events `ag_ui` can't decode.
  late final List<Map<String, Object?>> undecodable = [
    for (final json in rawEvents)
      if (_decode(json) == null) json,
  ];

  /// Whether the events were written by hand rather than recorded.
  bool get isSynthetic => header['source'] == 'synthetic';
}

/// Loads `test/fixtures/<name>.jsonl`.
Fixture loadFixture(String name) {
  final lines = File('test/fixtures/$name.jsonl')
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, Object?>)
      .toList();
  return Fixture(
    header: lines.first['fixture']! as Map<String, Object?>,
    rawEvents: lines.skip(1).toList(),
  );
}

BaseEvent? _decode(Map<String, Object?> json) {
  try {
    return const EventDecoder().decodeJson(json);
  } on DecodingError {
    return null;
  }
}
