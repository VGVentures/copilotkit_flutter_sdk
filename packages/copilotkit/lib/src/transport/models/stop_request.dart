import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'stop_request.g.dart';

/// Body of the runtime's stop route: which run of the thread to stop.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createFactory: false, ignoreUnannotated: true)
class const StopRequest({
  /// Id of the run to stop.
  @JsonKey() required final String runId,
}) extends Equatable {
  /// Creates a request to stop the run [runId].
  this;

  /// Encodes this request as the JSON body of the stop route.
  Map<String, Object?> toJson() => _$StopRequestToJson(this);

  @override
  List<Object?> get props => [runId];
}
