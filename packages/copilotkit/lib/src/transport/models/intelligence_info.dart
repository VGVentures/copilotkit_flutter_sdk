// cspell:ignore realtime
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'intelligence_info.g.dart';

/// What a runtime in `intelligence` mode tells a client about its
/// realtime service.
@JsonSerializable(createToJson: false)
class const IntelligenceInfo({
  /// The WebSocket URL of the realtime service, e.g.
  /// `wss://realtime.intelligence.copilotkit.ai/client`. Empty when the
  /// runtime doesn't say, for example because a newer one renamed it.
  @JsonKey(defaultValue: '') final String wsUrl = '',
}) extends Equatable {
  /// Creates the Intelligence part of the runtime info.
  this;

  /// Decodes the `intelligence` object of `GET /info`.
  factory fromJson(Map<String, Object?> json) =>
      _$IntelligenceInfoFromJson(json);

  @override
  List<Object?> get props => [wsUrl];
}
