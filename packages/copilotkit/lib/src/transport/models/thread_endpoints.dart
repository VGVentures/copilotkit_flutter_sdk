// cspell:ignore realtime
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'thread_endpoints.g.dart';

/// Which thread routes a runtime serves.
@JsonSerializable(createToJson: false)
class const ThreadEndpoints({
  /// Whether the runtime lists threads.
  @JsonKey(defaultValue: false) final bool list = false,

  /// Whether the runtime returns a thread's messages.
  @JsonKey(defaultValue: false) final bool inspect = false,

  /// Whether the runtime renames, archives and deletes threads.
  @JsonKey(defaultValue: false) final bool mutations = false,

  /// Whether the runtime pushes thread metadata changes in real time.
  @JsonKey(defaultValue: false) final bool realtimeMetadata = false,
}) extends Equatable {
  /// Creates the thread routes a runtime serves; by default, none.
  this;

  /// Decodes the `threadEndpoints` object of `GET /info`.
  factory fromJson(Map<String, Object?> json) =>
      _$ThreadEndpointsFromJson(json);

  @override
  List<Object?> get props => [list, inspect, mutations, realtimeMetadata];
}
