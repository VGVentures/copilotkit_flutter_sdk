import 'package:http/http.dart' as http;

/// `GET /info` answered with a status other than 2xx.
///
/// It is an [http.ClientException], so a caller that handles every failure to
/// read the info needs no change. [statusCode] tells a runtime that has no
/// `/info` route (`404`, `405`) from one that failed for now.
class const RuntimeInfoStatusException({
  required final int statusCode,
  @override required final String message,
  @override final Uri? uri,
}) implements http.ClientException {
  /// Creates the failure of a `/info` answered with [statusCode].
  this;

  /// Whether the runtime answered that it has no `/info` route, which will
  /// not change on a retry.
  bool get isMissing => statusCode == 404 || statusCode == 405;

  @override
  String toString() => 'ClientException: $message, uri=$uri';
}
