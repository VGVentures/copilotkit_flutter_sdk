import 'dart:convert';

import 'package:equatable/equatable.dart';

/// One message of the Phoenix v2 wire format, the JSON array
/// `[join_ref, ref, topic, event, payload]`.
class const PhoenixFrame({
  /// The topic the frame is for.
  required final String topic,

  /// The name of the event.
  required final String event,

  /// The payload, a JSON object.
  required final Map<String, Object?> payload,

  /// The ref of the join this frame belongs to, if any.
  final String? joinRef,

  /// The ref of this frame, which its reply repeats, if any.
  final String? ref,
}) extends Equatable {
  /// Creates a frame.
  this;

  /// Decodes the JSON text of a frame.
  ///
  /// Throws a [FormatException] when [text] isn't a Phoenix v2 frame. A
  /// payload that isn't a JSON object decodes as an empty one.
  factory decode(String text) {
    final fields = jsonDecode(text);
    if (fields case [
      final String? joinRef,
      final String? ref,
      final String topic,
      final String event,
      final Object? payload,
    ]) {
      return PhoenixFrame(
        joinRef: joinRef,
        ref: ref,
        topic: topic,
        event: event,
        payload: payload is Map<String, Object?> ? payload : const {},
      );
    }
    throw FormatException('Not a Phoenix v2 frame', text);
  }

  /// Encodes this frame as JSON text.
  String encode() => jsonEncode([joinRef, ref, topic, event, payload]);

  /// Whether this frame answers a join or a push.
  bool get isReply => event == 'phx_reply';

  /// The status of a reply, such as `ok` or `error`, or `null` if it has none.
  String? get status => switch (payload['status']) {
    final String status => status,
    _ => null,
  };

  /// The `response` of a reply.
  Object? get response => payload['response'];

  @override
  List<Object?> get props => [joinRef, ref, topic, event, payload];
}
