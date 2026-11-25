import 'package:copilotkit/src/threads/models/thread_metadata_operation.dart';
import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:equatable/equatable.dart';

/// A change to one of the user's threads, pushed by the runtime's real-time
/// service as it happens, whichever device made it.
class const ThreadMetadataEvent({
  /// What happened to the thread.
  required final ThreadMetadataOperation operation,

  /// The id of the thread.
  required final String threadId,

  /// When it happened.
  required final DateTime occurredAt,

  /// The thread as it is after the change, or `null` when it was deleted.
  final ThreadRecord? thread,
}) extends Equatable {
  /// Creates the event of [operation] on [threadId].
  this;

  /// Decodes the payload of a `thread_metadata` frame.
  ///
  /// Throws a [FormatException] for an operation this SDK doesn't know or a
  /// payload without a thread id, and a `CheckedFromJsonException` when the
  /// thread is malformed.
  factory fromJson(Map<String, Object?> json) {
    final name = json['operation'];
    final operation = ThreadMetadataOperation.values.asNameMap()[name];
    if (operation == null) {
      throw FormatException('Unknown thread operation: $name');
    }
    final threadId = json['threadId'];
    if (threadId is! String) {
      throw const FormatException('The event has no thread id.');
    }
    final thread = json['thread'];
    return ThreadMetadataEvent(
      operation: operation,
      threadId: threadId,
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      thread: operation == ThreadMetadataOperation.deleted || thread == null
          ? null
          : ThreadRecord.fromJson(thread as Map<String, Object?>),
    );
  }

  @override
  List<Object?> get props => [operation, threadId, occurredAt, thread];
}
