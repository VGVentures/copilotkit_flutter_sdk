import 'package:equatable/equatable.dart';

/// A frame the server pushed on a topic, other than a reply to something the
/// client sent.
class const PhoenixEvent({
  /// The topic the frame was pushed on.
  required final String topic,

  /// The name of the event, such as `ag_ui_event` or `phx_close`.
  required final String event,

  /// The frame's payload, a JSON object.
  required final Map<String, Object?> payload,
}) extends Equatable {
  /// Creates an event pushed on [topic].
  this;

  @override
  List<Object?> get props => [topic, event, payload];
}
