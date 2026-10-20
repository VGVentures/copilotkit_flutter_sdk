import 'package:json_annotation/json_annotation.dart';

part 'approval_args.g.dart';

/// Arguments of the `confirmAction` tool.
///
/// Mirrors the tool's Ack schema in `approval_demo.dart`; keep both in sync.
/// [action] is nullable, unlike in the schema, because `ApprovalCard` also
/// reads the partial args streamed before the call completes.
@JsonSerializable()
class const ApprovalArgs({final String? action}) {
  factory fromJson(Map<String, Object?> json) => _$ApprovalArgsFromJson(json);

  Map<String, Object?> toJson() => _$ApprovalArgsToJson(this);
}
