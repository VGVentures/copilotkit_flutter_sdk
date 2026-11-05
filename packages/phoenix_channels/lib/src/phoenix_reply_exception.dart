import 'package:equatable/equatable.dart';

/// Thrown when the server answers a join or a push with a status other than
/// `ok`.
class const PhoenixReplyException({
  /// The status of the reply, such as `error`.
  required final String status,

  /// The `response` of the reply, whatever the server sent.
  required final Object? response,
}) extends Equatable implements Exception {
  /// Creates the exception for a reply with [status] and [response].
  this;

  @override
  List<Object?> get props => [status, response];

  @override
  String toString() => 'PhoenixReplyException($status): $response';
}
