/// A client of the Phoenix channels protocol, version 2, over
/// `web_socket_channel`.
///
/// It opens one socket, joins one topic, pushes events and waits for their
/// replies, and streams what the server pushes. It does not reconnect: a
/// dropped connection is reported as an error and the caller decides what to
/// do, because only the caller knows how to get new credentials.
library;

export 'src/phoenix_client.dart';
export 'src/phoenix_closed_exception.dart';
export 'src/phoenix_event.dart';
export 'src/phoenix_reply_exception.dart';
