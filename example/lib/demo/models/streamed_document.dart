import 'package:copilotkit_flutter/copilotkit_flutter.dart';
import 'package:equatable/equatable.dart';

/// The document the agent writes into the shared state, under `document`.
///
/// The runtime streams it into the state while the agent writes it, so a
/// value can be partial. The user edits it too.
class const StreamedDocument({final String text = ''}) extends Equatable {
  /// Creates a document with [text].
  this;

  /// The document in [shared], or an empty one when there is none, or when
  /// `document` is missing or isn't a string.
  factory fromShared(SharedState? shared) {
    final document = shared?.toJson()[key];
    return StreamedDocument(text: document is String ? document : '');
  }

  /// Key of the document in the shared state.
  static const key = 'document';

  /// Returns [current] with this document in place of its `document`, and
  /// everything else in it (the todo list, for example) kept.
  SharedState toShared(SharedState? current) =>
      SharedState({...?current?.toJson(), key: text});

  @override
  List<Object?> get props => [text];
}
