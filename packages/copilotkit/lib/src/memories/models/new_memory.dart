import 'package:copilotkit/src/memories/models/memory_kind.dart';
import 'package:copilotkit/src/memories/models/memory_scope.dart';
import 'package:copilotkit/src/memories/models/memory_validation_exception.dart';
import 'package:equatable/equatable.dart';

/// What a memory to save, or a memory that replaces another, says.
///
/// To supersede a memory, pass the whole new memory: it replaces the old one
/// and is not a patch. Leaving out [sourceThreadIds] resets them to none
/// instead of keeping the old memory's.
class const NewMemory({
  /// What to remember. At most [maxContentLength] characters.
  required final String content,

  /// What the memory is about.
  required final MemoryKind kind,

  /// Who can see the memory, or `null` for the runtime's default, which is
  /// [MemoryScope.user].
  final MemoryScope? scope,

  /// The threads the memory came from. At most [maxSourceThreadIds].
  final List<String> sourceThreadIds = const [],
}) extends Equatable {
  /// Creates a memory to save.
  this;

  /// The most characters [content] can have.
  static const maxContentLength = 8192;

  /// The most ids [sourceThreadIds] can have.
  static const maxSourceThreadIds = 100;

  /// Throws a [MemoryValidationException] when this memory breaks a limit of
  /// the runtime, which rejects it otherwise.
  void validate() {
    if (content.length > maxContentLength) {
      throw const MemoryValidationException(
        'content is longer than $maxContentLength characters.',
      );
    }
    if (sourceThreadIds.length > maxSourceThreadIds) {
      throw const MemoryValidationException(
        'sourceThreadIds has more than $maxSourceThreadIds ids.',
      );
    }
  }

  /// The JSON body of the runtime's save and supersede routes.
  ///
  /// It holds only the fields the runtime knows, since it rejects the others.
  Map<String, Object?> toJson() => {
    'content': content,
    'kind': kind.wireName,
    'scope': ?scope?.wireName,
    'sourceThreadIds': sourceThreadIds,
  };

  @override
  List<Object?> get props => [content, kind, scope, sourceThreadIds];
}
