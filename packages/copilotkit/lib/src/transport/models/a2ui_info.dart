import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'a2ui_info.g.dart';

/// The A2UI settings of a runtime that has A2UI on.
@JsonSerializable(createToJson: false)
class const A2uiInfo({
  /// The ids of the agents A2UI is limited to, or empty when the runtime
  /// doesn't limit it.
  final List<String> agents = const [],
}) extends Equatable {
  /// Creates the A2UI part of the runtime info.
  this;

  /// Decodes the `a2ui` object of `GET /info`.
  factory fromJson(Map<String, Object?> json) => _$A2uiInfoFromJson(json);

  @override
  List<Object?> get props => [agents];
}
