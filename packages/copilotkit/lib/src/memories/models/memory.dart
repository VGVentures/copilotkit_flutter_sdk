import 'package:copilotkit/src/memories/models/memory_kind.dart';
import 'package:copilotkit/src/memories/models/memory_scope.dart';
import 'package:equatable/equatable.dart';

/// A long-term memory about a user, which outlives any thread.
class const Memory({
  /// The id of the memory. Superseding a memory gives the new one another id.
  required final String id,

  /// What the memory is about.
  required final MemoryKind kind,

  /// Who can see the memory.
  required final MemoryScope scope,

  /// What is remembered.
  required final String content,

  /// The threads the memory came from.
  required final List<String> sourceThreadIds,

  /// How well the memory matches the query of a recall, or `null` for a
  /// memory that wasn't recalled.
  final double? score,

  /// When the memory was retired, or `null` while it is live.
  ///
  /// Only a list with `includeInvalidated` returns retired memories.
  final DateTime? invalidatedAt,
}) extends Equatable {
  /// Creates a memory.
  this;

  /// Reads a memory from the JSON the runtime sends, ignoring fields this SDK
  /// doesn't know.
  ///
  /// Throws a [FormatException] when a field is missing or has the wrong
  /// type.
  factory fromJson(Map<String, Object?> json) {
    final kind = MemoryKind.fromWireName(json['kind']);
    final scope = MemoryScope.fromWireName(json['scope']);
    final id = json['id'];
    final content = json['content'];
    final sourceThreadIds = json['sourceThreadIds'];
    final score = json['score'];
    final invalidatedAt = json['invalidatedAt'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Memory has no valid id.');
    }
    if (kind == null) throw const FormatException('Memory has no valid kind.');
    if (scope == null) {
      throw const FormatException('Memory has no valid scope.');
    }
    if (content is! String) {
      throw const FormatException('Memory has no valid content.');
    }
    if (sourceThreadIds is! List ||
        !sourceThreadIds.every((id) => id is String)) {
      throw const FormatException('Memory has no valid sourceThreadIds.');
    }
    if (score != null && score is! num) {
      throw const FormatException('Memory has an invalid score.');
    }
    if (invalidatedAt != null && invalidatedAt is! String) {
      throw const FormatException('Memory has an invalid invalidatedAt.');
    }
    return Memory(
      id: id,
      kind: kind,
      scope: scope,
      content: content,
      sourceThreadIds: List.unmodifiable(sourceThreadIds.cast<String>()),
      score: (score as num?)?.toDouble(),
      invalidatedAt: invalidatedAt == null
          ? null
          : DateTime.parse(invalidatedAt as String),
    );
  }

  /// Whether the memory was retired.
  bool get isRetired => invalidatedAt != null;

  @override
  List<Object?> get props => [
    id,
    kind,
    scope,
    content,
    sourceThreadIds,
    score,
    invalidatedAt,
  ];
}
