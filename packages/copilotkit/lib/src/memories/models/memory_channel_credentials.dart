import 'package:equatable/equatable.dart';

/// What the runtime's `POST /memories/subscribe` grants: a join token and
/// code for the user's memory channel, the project's, or both.
class const MemoryChannelCredentials({
  /// The token of the socket for the user's channel.
  final String? joinToken,

  /// The code of the user's channel, `user_meta:memories:<joinCode>`.
  final String? joinCode,

  /// The token of the socket for the project's channel.
  final String? projectJoinToken,

  /// The code of the project's channel,
  /// `project_meta:memories:<projectJoinCode>`.
  final String? projectJoinCode,
}) extends Equatable {
  /// Creates the credentials.
  this;

  /// Decodes the body of `POST /memories/subscribe`.
  ///
  /// Throws a [FormatException] when it has neither a complete user pair nor
  /// a complete project pair.
  factory fromJson(Map<String, Object?> json) {
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    final credentials = MemoryChannelCredentials(
      joinToken: text('joinToken'),
      joinCode: text('joinCode'),
      projectJoinToken: text('projectJoinToken'),
      projectJoinCode: text('projectJoinCode'),
    );
    if (credentials.userTopic == null && credentials.projectTopic == null) {
      throw const FormatException('The body has no join token and code.');
    }
    return credentials;
  }

  /// The topic of the user's channel, or `null` without a user pair.
  String? get userTopic => joinToken != null && joinCode != null
      ? 'user_meta:memories:$joinCode'
      : null;

  /// The topic of the project's channel, or `null` without a project pair.
  String? get projectTopic =>
      projectJoinToken != null && projectJoinCode != null
      ? 'project_meta:memories:$projectJoinCode'
      : null;

  @override
  List<Object?> get props => [
    joinToken,
    joinCode,
    projectJoinToken,
    projectJoinCode,
  ];
}
