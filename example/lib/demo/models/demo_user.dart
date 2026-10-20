import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'demo_user.g.dart';

/// Placeholder user shared with the agent as context.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createFactory: false, ignoreUnannotated: true)
class const DemoUser({
  /// First name of the user.
  @JsonKey() required final String name,

  /// City the user lives in.
  @JsonKey() required final String homeCity,
}) extends Equatable {
  /// Creates a user.
  this;

  /// The user the demo shares with the agent.
  static const ada = DemoUser(name: 'Ada', homeCity: 'Lima');

  /// Returns this user as JSON, the value shared with the agent.
  Map<String, Object?> toJson() => _$DemoUserToJson(this);

  @override
  List<Object?> get props => [name, homeCity];
}
