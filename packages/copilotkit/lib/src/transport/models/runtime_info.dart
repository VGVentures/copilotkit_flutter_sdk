// cspell:ignore realtime
import 'package:copilotkit/src/transport/models/a2ui_info.dart';
import 'package:copilotkit/src/transport/models/intelligence_info.dart';
import 'package:copilotkit/src/transport/models/runtime_agent_info.dart';
import 'package:copilotkit/src/transport/models/runtime_mode.dart';
import 'package:copilotkit/src/transport/models/thread_endpoints.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'runtime_info.g.dart';

/// What a Copilot Runtime says about itself at `GET /info`.
///
/// Runtimes add fields often, so unknown fields are ignored and every field
/// has a default: a runtime that says nothing is an SSE runtime with no
/// thread routes and no A2UI.
@JsonSerializable(createToJson: false)
class const RuntimeInfo({
  /// The runtime's version, e.g. `1.79.0`.
  @JsonKey(defaultValue: '') final String version = '',

  /// How the runtime delivers the events of a run. A mode this SDK doesn't
  /// know is [RuntimeMode.sse].
  @JsonKey(unknownEnumValue: RuntimeMode.sse)
  final RuntimeMode mode = RuntimeMode.sse,

  /// The realtime service, present when [mode] is [RuntimeMode.intelligence].
  final IntelligenceInfo? intelligence,

  /// Which thread routes the runtime serves.
  final ThreadEndpoints threadEndpoints = const ThreadEndpoints(),

  /// Whether the runtime has A2UI on.
  @JsonKey(defaultValue: false) final bool a2uiEnabled = false,

  /// The A2UI settings, present when [a2uiEnabled].
  final A2uiInfo? a2ui,

  /// The agents the runtime serves, by id.
  final Map<String, RuntimeAgentInfo> agents = const {},
}) extends Equatable {
  /// Creates the info of a runtime; by default, an SSE runtime.
  this;

  /// Decodes the JSON body of `GET /info`.
  factory fromJson(Map<String, Object?> json) => _$RuntimeInfoFromJson(json);

  @override
  List<Object?> get props => [
    version,
    mode,
    intelligence,
    threadEndpoints,
    a2uiEnabled,
    a2ui,
    agents,
  ];
}
