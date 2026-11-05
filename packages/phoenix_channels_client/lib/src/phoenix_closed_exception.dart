import 'package:equatable/equatable.dart';

/// Reported when the connection ended: the server or the network closed the
/// socket, or the client was closed while a push still waited for its reply.
///
/// A client that ended can't be reused. Create a new one.
class const PhoenixClosedException({
  /// The WebSocket close code, if the socket reported one.
  final int? code,

  /// The WebSocket close reason, if the socket reported one.
  final String? reason,
}) extends Equatable implements Exception {
  /// Creates the exception for a socket closed with [code] and [reason].
  this;

  @override
  List<Object?> get props => [code, reason];

  @override
  String toString() => 'PhoenixClosedException(code: $code, reason: $reason)';
}
