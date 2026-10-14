import 'package:json_annotation/json_annotation.dart';

part 'stop_request.g.dart';

/// Body of the runtime's stop route: which run of the thread to stop.
@JsonSerializable(createFactory: false)
class const StopRequest({
  /// Id of the run to stop.
  required final String runId,
}) {
  /// Creates a request to stop the run [runId].
  this;

  /// Encodes this request as the JSON body of the stop route.
  Map<String, Object?> toJson() => _$StopRequestToJson(this);
}
