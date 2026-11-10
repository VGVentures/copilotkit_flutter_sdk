import 'package:json_annotation/json_annotation.dart';

/// How a Copilot Runtime delivers the events of a run.
enum RuntimeMode {
  /// The run streams over the HTTP response, as Server-Sent Events.
  @JsonValue('sse')
  sse,

  /// The run streams over a Phoenix channel, with CopilotKit Intelligence.
  @JsonValue('intelligence')
  intelligence,
}
