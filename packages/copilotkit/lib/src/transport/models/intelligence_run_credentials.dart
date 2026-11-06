// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/intelligence_realtime.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'intelligence_run_credentials.g.dart';

/// The answer of an Intelligence runtime to `POST /agent/{id}/run`: the run
/// it started, and what to join to receive its events.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createToJson: false, ignoreUnannotated: true)
class const IntelligenceRunCredentials({
  /// The thread the run belongs to. The runtime may answer with a different
  /// id than the one requested, and then this is the one to use.
  @JsonKey() required final String threadId,

  /// The run the runtime started. Like [threadId], it is the runtime's own.
  @JsonKey() required final String runId,

  /// The token to join the channel with. It is single-use.
  @JsonKey() required final String joinToken,

  /// Where the run's events arrive.
  @JsonKey() required final IntelligenceRealtime realtime,
}) extends Equatable {
  /// Creates the credentials of a run.
  this;

  /// Decodes the JSON body of the run response.
  ///
  /// Throws a `CheckedFromJsonException` when a field is missing or has the
  /// wrong type.
  factory fromJson(Map<String, Object?> json) =>
      _$IntelligenceRunCredentialsFromJson(json);

  @override
  List<Object?> get props => [threadId, runId, joinToken, realtime];
}
