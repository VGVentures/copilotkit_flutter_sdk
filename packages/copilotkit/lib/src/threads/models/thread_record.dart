import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'thread_record.g.dart';

/// A conversation the runtime keeps, as its thread routes list it.
///
/// The runtime sends more than this, such as the organization and the
/// Learning container. Only what an app lists and manages is kept.
// Equatable's getters would be serialized too, so only annotated fields are.
@JsonSerializable(createToJson: false, ignoreUnannotated: true)
class const ThreadRecord({
  /// The id of the thread: the one to open an agent on.
  @JsonKey() required final String id,

  /// The agent the thread belongs to.
  @JsonKey() required final String agentId,

  /// Whether the thread is archived, so hidden from the default list.
  @JsonKey() required final bool archived,

  /// When the thread was created.
  @JsonKey() required final DateTime createdAt,

  /// When the thread last changed, which is what the list is sorted by.
  @JsonKey() required final DateTime updatedAt,

  /// The name of the thread, or `null` while it has none.
  ///
  /// The runtime names a thread after its first messages.
  @JsonKey() final String? name,
}) extends Equatable {
  /// Creates a thread record.
  this;

  /// Decodes one thread of the runtime's JSON.
  ///
  /// Throws a `CheckedFromJsonException` when a field is missing or has the
  /// wrong type.
  factory fromJson(Map<String, Object?> json) => _$ThreadRecordFromJson(json);

  /// Returns a copy with [name] or [archived] changed.
  ///
  /// A name can be set but not cleared: the runtime names a thread, and an
  /// app that renames it gives it a name.
  ThreadRecord copyWith({String? name, bool? archived}) => ThreadRecord(
    id: id,
    agentId: agentId,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt,
    name: name ?? this.name,
  );

  @override
  List<Object?> get props => [
    id,
    agentId,
    name,
    archived,
    createdAt,
    updatedAt,
  ];
}
