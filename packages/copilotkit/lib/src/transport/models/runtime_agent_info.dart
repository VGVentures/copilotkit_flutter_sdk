import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'runtime_agent_info.g.dart';

/// An agent a runtime serves, as `GET /info` lists it.
@JsonSerializable(createToJson: false)
class const RuntimeAgentInfo({
  /// The agent's id.
  required final String name,

  /// What the agent does, or empty when the runtime doesn't say.
  @JsonKey(defaultValue: '') final String description = '',
}) extends Equatable {
  /// Creates an agent the runtime serves.
  this;

  /// Decodes one entry of the `agents` object of `GET /info`.
  factory fromJson(Map<String, Object?> json) =>
      _$RuntimeAgentInfoFromJson(json);

  @override
  List<Object?> get props => [name, description];
}
