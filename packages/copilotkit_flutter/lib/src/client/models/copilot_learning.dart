import 'package:equatable/equatable.dart';

/// How a `CopilotKit` captures a trajectory for Automatic Learning.
///
/// Capturing is opt-in: it records the routes the user visits and the
/// controls marked with `CopilotAction` they tap, plus the app's own events.
/// It records no text the user types. Ask for the user's consent first.
class const CopilotLearning({
  /// The trajectory to capture, a UUID, or `null` for a new one.
  final String? trajectoryId,
}) extends Equatable {
  /// Creates the learning configuration.
  this;

  @override
  List<Object?> get props => [trajectoryId];
}
