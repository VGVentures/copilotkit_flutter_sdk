import 'package:copilotkit/src/memories/models/memory.dart';
import 'package:equatable/equatable.dart';

/// What the runtime did with a memory that was saved or superseded.
class const MemoryMutationOutcome({
  /// The memory that was stored.
  ///
  /// When [isAbsorbed], it is the memory the content was merged into.
  required final Memory memory,

  /// Whether the runtime merged the content into a near-duplicate memory
  /// instead of storing a new one.
  final bool isAbsorbed = false,

  /// The id of the memory a supersede retired, or `null` for a save.
  final String? retiredId,
}) extends Equatable {
  /// Creates the outcome of a save or supersede.
  this;

  @override
  List<Object?> get props => [memory, isAbsorbed, retiredId];
}
