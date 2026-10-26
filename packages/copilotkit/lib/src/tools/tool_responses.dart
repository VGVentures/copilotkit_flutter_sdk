import 'dart:async';
import 'dart:convert';

import 'package:copilotkit/src/tools/cancellation_signal.dart';
import 'package:copilotkit/src/tools/models/fallback_tool_result.dart';

/// The user's answers to human-in-the-loop tool calls, by tool call id.
///
/// An answer can arrive before the turn waits for it, and the turn must wake
/// up when it does, so both sides share one completer per call, created by
/// whichever comes first. It is mutable: a documented exception to the
/// immutability rule (ADR 0009).
class ToolResponses() {
  /// Creates an empty store.
  this;

  final _responses = <String, Completer<String>>{};

  /// Whether the call [toolCallId] has been answered and not [remove]d yet.
  bool isAnswered(String toolCallId) =>
      _responses[toolCallId]?.isCompleted ?? false;

  /// Answers the call [toolCallId] with [result]: a [String] as it is,
  /// anything else JSON-encoded.
  ///
  /// Only the first answer counts; later ones are ignored. Throws a
  /// [JsonUnsupportedObjectError] when [result] can't be encoded, and the
  /// call stays unanswered.
  void respond(String toolCallId, Object? result) {
    final text = switch (result) {
      final String text => text,
      _ => jsonEncode(result),
    };
    final completer = _responses.putIfAbsent(toolCallId, Completer.new);
    if (!completer.isCompleted) completer.complete(text);
  }

  /// Waits for the answer to the call [toolCallId] and returns it, or the
  /// cancelled result once [signal] is cancelled.
  ///
  /// An answer that arrived earlier is returned right away.
  Future<String> wait(String toolCallId, CancellationSignal signal) async {
    final completer = _responses.putIfAbsent(toolCallId, Completer.new);
    await Future.any([completer.future, signal.whenCancelled]);
    return completer.isCompleted
        ? await completer.future
        : FallbackToolResult.cancelled.message;
  }

  /// Forgets the call [toolCallId], once it has its result.
  void remove(String toolCallId) => _responses.remove(toolCallId);

  /// Forgets every call.
  void clear() => _responses.clear();
}
