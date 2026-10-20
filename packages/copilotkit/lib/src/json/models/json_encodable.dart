/// A value sent to the agent as JSON, e.g. a context value.
///
/// `jsonEncode` calls [toJson], so implement it on the app's models, e.g.
/// with `json_serializable`.
abstract interface class JsonEncodable {
  /// Returns this value as JSON: a map, list, string, number, bool or
  /// `null`.
  Object? toJson();
}
