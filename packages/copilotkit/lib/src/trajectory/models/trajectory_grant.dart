// cspell:ignore realtime
import 'package:equatable/equatable.dart';

/// What the runtime's `POST /trajectory/{id}/connect` grants: the token and
/// the channel to capture a trajectory on.
class const TrajectoryGrant({
  /// The token of the socket, sent as `join_token`.
  required final String joinToken,

  /// The socket of the real-time service, e.g.
  /// `wss://realtime.intelligence.copilotkit.ai/client`.
  required final Uri clientUrl,

  /// The channel of the trajectory, `trajectory:<id>`.
  required final String topic,
}) extends Equatable {
  /// Creates a grant.
  this;

  /// Decodes the body of the runtime's answer.
  ///
  /// Throws a [FormatException] when a field is missing or empty.
  factory fromJson(Map<String, Object?> json) {
    if (json
        case {
          'joinToken': final String joinToken,
          'realtime': {
            'clientUrl': final String clientUrl,
            'topic': final String topic,
          },
        }
        when joinToken.isNotEmpty && clientUrl.isNotEmpty && topic.isNotEmpty) {
      return TrajectoryGrant(
        joinToken: joinToken,
        clientUrl: Uri.parse(clientUrl),
        topic: topic,
      );
    }
    throw const FormatException('The body is not a trajectory grant.');
  }

  @override
  List<Object?> get props => [joinToken, clientUrl, topic];
}
