// cspell:ignore realtime
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'intelligence_realtime.g.dart';

/// Where the events of an Intelligence run arrive: the Phoenix socket to
/// connect to and the topic to join on it.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createToJson: false, ignoreUnannotated: true)
class const IntelligenceRealtime({
  /// The URL of the Phoenix socket, e.g.
  /// `wss://realtime.intelligence.copilotkit.ai/client`.
  @JsonKey() required final String clientUrl,

  /// The topic to join on the socket, e.g. `thread:<threadId>`.
  @JsonKey() required final String topic,
}) extends Equatable {
  /// Creates the realtime location of a run.
  this;

  /// Decodes the `realtime` object of the runtime's run response.
  ///
  /// Throws a `CheckedFromJsonException` when a field is missing.
  factory fromJson(Map<String, Object?> json) =>
      _$IntelligenceRealtimeFromJson(json);

  @override
  List<Object?> get props => [clientUrl, topic];
}
