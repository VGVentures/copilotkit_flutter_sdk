import 'package:copilotkit/src/threads/models/thread_record.dart';
import 'package:equatable/equatable.dart';

/// One page of the threads of an agent, newest first.
class const ThreadPage({
  /// The threads of the page.
  required final List<ThreadRecord> threads,

  /// The cursor of the next page, or `null` on the last one.
  final String? nextCursor,

  /// The code of the user's thread metadata channel, or `null` when the
  /// runtime has no real-time service. Pass it to
  /// `CopilotKitClient.watchThreads` to follow changes live.
  final String? joinCode,
}) extends Equatable {
  /// Creates a page of [threads].
  this;

  /// Decodes the body of the runtime's `GET /threads`, with a read-only list
  /// of threads.
  ///
  /// Throws a [FormatException] when the body has no list of threads, and a
  /// `CheckedFromJsonException` when a thread is malformed.
  factory fromJson(Map<String, Object?> json) {
    final threads = json['threads'];
    if (threads is! List) {
      throw const FormatException('The body has no threads list.');
    }
    return ThreadPage(
      threads: List.unmodifiable([
        for (final thread in threads)
          ThreadRecord.fromJson(thread! as Map<String, Object?>),
      ]),
      nextCursor: json['nextCursor'] as String?,
      joinCode: json['joinCode'] as String?,
    );
  }

  /// Whether another page follows.
  bool get hasNext => nextCursor != null;

  @override
  List<Object?> get props => [threads, nextCursor, joinCode];
}
