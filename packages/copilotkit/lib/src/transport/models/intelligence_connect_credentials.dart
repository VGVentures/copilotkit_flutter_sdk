// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/intelligence_realtime.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'intelligence_connect_credentials.g.dart';

/// The answer of an Intelligence runtime to `POST /agent/{id}/connect`: what
/// to join to receive the replay of a thread.
///
/// Unlike the answer to a run, it names no run: a replay is not one.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createToJson: false, ignoreUnannotated: true)
class const IntelligenceConnectCredentials({
  /// The thread to replay. The runtime may answer with a different id than the
  /// one requested, and then this is the one to use.
  @JsonKey() required final String threadId,

  /// The token to join the channel with. It is single-use.
  @JsonKey() required final String joinToken,

  /// Where the replay arrives.
  @JsonKey() required final IntelligenceRealtime realtime,
}) extends Equatable {
  /// Creates the credentials of a replay.
  this;

  /// Decodes the JSON body of the connect response.
  ///
  /// Throws a `CheckedFromJsonException` when a field is missing or has the
  /// wrong type.
  factory fromJson(Map<String, Object?> json) =>
      _$IntelligenceConnectCredentialsFromJson(json);

  @override
  List<Object?> get props => [threadId, joinToken, realtime];
}
