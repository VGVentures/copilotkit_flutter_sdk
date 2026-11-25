import 'package:copilotkit/src/memories/models/memory.dart';
import 'package:copilotkit/src/memories/models/memory_metadata_operation.dart';
import 'package:equatable/equatable.dart';

/// A change to one of the user's or the project's memories, pushed by the
/// runtime's real-time service as it happens.
class const MemoryMetadataEvent({
  /// What happened to the memory.
  required final MemoryMetadataOperation operation,

  /// The id of the memory.
  required final String memoryId,

  /// When it happened.
  required final DateTime occurredAt,

  /// The memory as it is after the change, or `null` when it was
  /// invalidated.
  final Memory? memory,
}) extends Equatable {
  /// Creates the event of [operation] on [memoryId].
  this;

  /// Decodes the payload of a `memory_metadata` frame.
  ///
  /// Throws a [FormatException] for an operation this SDK doesn't know, a
  /// payload without a memory id, or a created or updated memory that is
  /// missing or malformed.
  factory fromJson(Map<String, Object?> json) {
    final name = json['operation'];
    final operation = MemoryMetadataOperation.values.asNameMap()[name];
    if (operation == null) {
      throw FormatException('Unknown memory operation: $name');
    }
    final memoryId = json['memoryId'];
    if (memoryId is! String || memoryId.isEmpty) {
      throw const FormatException('The event has no memory id.');
    }
    final memory = json['memory'];
    if (operation != MemoryMetadataOperation.invalidated &&
        memory is! Map<String, Object?>) {
      throw const FormatException('The event has no memory.');
    }
    return MemoryMetadataEvent(
      operation: operation,
      memoryId: memoryId,
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      memory: operation == MemoryMetadataOperation.invalidated
          ? null
          : Memory.fromJson(memory! as Map<String, Object?>),
    );
  }

  @override
  List<Object?> get props => [operation, memoryId, occurredAt, memory];
}
