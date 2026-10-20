import 'package:equatable/equatable.dart';

/// What running a frontend tool call produced.
class const ToolCallOutcome({
  /// The result text sent to the agent.
  required final String result,

  /// The error the handler threw, or `null`.
  ///
  /// The agent only gets a generic
  /// [result]; report the error to the app instead.
  final Object? error,

  /// Where [error] was thrown, or `null` when there is no error.
  final StackTrace? stackTrace,
}) extends Equatable {
  /// Creates the outcome of a tool call.
  this;

  @override
  List<Object?> get props => [result, error, stackTrace];
}
