import 'package:equatable/equatable.dart';

/// Where a Phoenix socket connects: the URL the server gave, and the
/// parameters to send with the handshake.
class const PhoenixEndpoint({
  /// The URL of the socket, without the `/websocket` transport path.
  required final Uri url,

  /// The query parameters to send, such as a join token.
  required final Map<String, String> params,
}) extends Equatable {
  /// Creates the endpoint at [url] that sends [params].
  this;

  /// The URL to open: `/websocket` is appended to the path, unless it already
  /// ends with it, and the query has the version of the protocol and [params]
  /// next to any query [url] already had.
  Uri get socketUrl {
    final path = url.path.endsWith('/websocket')
        ? url.path
        : '${url.path.replaceFirst(RegExp(r'/+$'), '')}/websocket';
    return url.replace(
      path: path,
      queryParameters: {...url.queryParameters, ...params, 'vsn': '2.0.0'},
    );
  }

  @override
  List<Object?> get props => [url, params];
}
